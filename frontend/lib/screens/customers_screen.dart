import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/customer_export.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/export_sheet.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/skeletons.dart';
import 'history_screen.dart' show BillDetailDialog;

final _dateFmt = DateFormat('dd MMM yyyy');

// ---------------------------------------------------------------------------
// Filtering — the model is pure; the server applies it (see toQuery).
// ---------------------------------------------------------------------------

/// When the customer last bought. `within*` = came in during the last N days;
/// `inactive*` = has NOT come in for N days or more (win-back campaigns).
enum CustomerRecency { any, within7, within30, within90, inactive30, inactive60, inactive90 }

enum CustomerOffers { all, allowed, optedOut }

enum CustomerSort { spend, visits, recent, name }

/// Everything the Customers list can be narrowed by (search is separate).
@immutable
class CustomerFilter {
  final int? minVisits;
  final int? maxVisits;
  final double? minSpend;
  final double? maxSpend;
  final CustomerRecency recency;
  final CustomerOffers offers;

  const CustomerFilter({
    this.minVisits,
    this.maxVisits,
    this.minSpend,
    this.maxSpend,
    this.recency = CustomerRecency.any,
    this.offers = CustomerOffers.all,
  });

  static const none = CustomerFilter();

  int get activeCount => [
        minVisits != null || maxVisits != null,
        minSpend != null || maxSpend != null,
        recency != CustomerRecency.any,
        offers != CustomerOffers.all,
      ].where((b) => b).length;

  /// Server query parameters (GET /api/customers) — the server does the
  /// filtering so the app only ever holds one page.
  Map<String, String> toQuery() => {
        if (minVisits != null) 'min_visits': '$minVisits',
        if (maxVisits != null) 'max_visits': '$maxVisits',
        if (minSpend != null) 'min_spend': _num(minSpend!),
        if (maxSpend != null) 'max_spend': _num(maxSpend!),
        if (recency != CustomerRecency.any) 'recency': recency.name,
        if (offers == CustomerOffers.allowed) 'offers': 'allowed',
        if (offers == CustomerOffers.optedOut) 'offers': 'opted_out',
      };

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  bool operator ==(Object other) =>
      other is CustomerFilter &&
      other.minVisits == minVisits &&
      other.maxVisits == maxVisits &&
      other.minSpend == minSpend &&
      other.maxSpend == maxSpend &&
      other.recency == recency &&
      other.offers == offers;

  @override
  int get hashCode =>
      Object.hash(minVisits, maxVisits, minSpend, maxSpend, recency, offers);
}

/// Search + filter + sort as one request, so the list, its counts, "Select
/// all" and the filter sheet's "Show N" all ask the server the same question.
Map<String, String> customerListParams({
  String query = '',
  CustomerFilter filter = CustomerFilter.none,
  CustomerSort sort = CustomerSort.spend,
  bool descending = true,
}) =>
    {
      ...filter.toQuery(),
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'sort': sort.name,
      'dir': descending ? 'desc' : 'asc',
    };

// Server page cap for both customer endpoints (PAGE_MAX in customers.js), so
// exports walk every page in as few requests as possible.
const _exportPageSize = 100;

/// Date stamp for export file names, e.g. 07-Oct-2026.
String _fileDate() => DateFormat('dd-MMM-yyyy').format(DateTime.now());

void _exportFailed(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('${context.l10n.exportFailed}: ${sanitizeUiErrorMessage(e)}'),
    backgroundColor: AppColors.error,
  ));
}

/// Top-bar export button (Excel/PDF, then download/share); a spinner while the
/// file is built.
class _ExportButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  const _ExportButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.exportTitle,
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.file_download_outlined),
      );
}

String _money(double v) =>
    '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

String _range<T extends num>(T? min, T? max, String Function(T) fmt) {
  if (min != null && max != null) {
    return min == max ? fmt(min) : '${fmt(min)}–${fmt(max)}';
  }
  if (min != null) return '${fmt(min)}+';
  return '≤ ${fmt(max as T)}';
}

String _recencyLabel(AppLocalizations l10n, CustomerRecency r) => switch (r) {
      CustomerRecency.any => l10n.customersRecencyAny,
      CustomerRecency.within7 => l10n.customersRecencyWithin(7),
      CustomerRecency.within30 => l10n.customersRecencyWithin(30),
      CustomerRecency.within90 => l10n.customersRecencyWithin(90),
      CustomerRecency.inactive30 => l10n.customersRecencyInactive(30),
      CustomerRecency.inactive60 => l10n.customersRecencyInactive(60),
      CustomerRecency.inactive90 => l10n.customersRecencyInactive(90),
    };

String _sortLabel(AppLocalizations l10n, CustomerSort s) => switch (s) {
      CustomerSort.spend => l10n.customersSortSpend,
      CustomerSort.visits => l10n.customersSortVisits,
      CustomerSort.recent => l10n.customersSortRecent,
      CustomerSort.name => l10n.customersSortName,
    };

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Owner's customer base: everyone with a finalized bill, their visits and
/// spend. Select customers → Next → type one message → it goes to all of them
/// on WhatsApp. Opted-out customers can be seen but never selected.
///
/// Paged: the server filters, sorts and returns [_pageSize] at a time; the
/// next page loads as the list nears its end.
class CustomersScreen extends ConsumerStatefulWidget {
  /// One page of customers for the given query params; defaults to the API.
  /// Tests pass a fake.
  final Future<Map<String, dynamic>> Function(Map<String, String> params)
      loadCustomers;

  /// Every matching, messageable id ("Select all"); defaults to the API.
  final Future<List<String>> Function(Map<String, String> params) loadIds;

  const CustomersScreen({
    super.key,
    this.loadCustomers = getCustomers,
    this.loadIds = getCustomerIds,
  });

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  static const _pageSize = 30;

  List<Customer> _items = const [];
  int _total = 0; // matching the current search/filters
  int _totalAll = 0; // every customer of the shop
  int _totalEligible = 0; // matching AND not opted out
  bool _loading = true; // first page
  bool _refreshing = false; // new search/filter/sort over an existing list
  bool _loadingMore = false;
  bool _selectingAll = false;
  bool _exporting = false;
  Object? _error;
  // Bumped on every new query so a late response for an old one is dropped.
  int _requestSeq = 0;

  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  CustomerFilter _filter = CustomerFilter.none;
  CustomerSort _sort = CustomerSort.spend;
  bool _descending = true;
  final Set<String> _selected = {};

  bool get _hasMore => _items.length < _total;

  Map<String, String> get _params => customerListParams(
      query: _query, filter: _filter, sort: _sort, descending: _descending);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// First page for the current search/filters/sort, replacing the list.
  Future<void> _reload() async {
    final seq = ++_requestSeq;
    setState(() {
      // First open: skeleton page. Later (search/filter/sort): keep showing
      // the current list under a thin progress bar instead of blanking it.
      _loading = _items.isEmpty;
      _refreshing = _items.isNotEmpty;
      _error = null;
    });
    try {
      final r = await widget.loadCustomers(
          {..._params, 'offset': '0', 'limit': '$_pageSize'});
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _applyCounts(r);
        _items = _parse(r);
        _loading = false;
        _refreshing = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e;
      });
    }
  }

  /// Next page, appended. Ignored while one is already loading or at the end.
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final r = await widget.loadCustomers(
          {..._params, 'offset': '${_items.length}', 'limit': '$_pageSize'});
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _applyCounts(r);
        final seen = _items.map((c) => c.id).toSet();
        _items = [..._items, ..._parse(r).where((c) => !seen.contains(c.id))];
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sanitizeUiErrorMessage(e)),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loadingMore = false);
    }
  }

  static List<Customer> _parse(Map<String, dynamic> r) => (r['items'] as List)
      .map((j) => Customer.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();

  void _applyCounts(Map<String, dynamic> r) {
    _total = (r['total'] as num?)?.toInt() ?? 0;
    _totalAll = (r['total_all'] as num?)?.toInt() ?? 0;
    _totalEligible = (r['total_eligible'] as num?)?.toInt() ?? 0;
  }

  void _setFilter(CustomerFilter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    _reload();
  }

  void _setSort(CustomerSort sort, bool descending) {
    setState(() {
      _sort = sort;
      _descending = descending;
    });
    _reload();
  }

  void _onSearchChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  void _clearSearchAndFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _filter = CustomerFilter.none;
      _searchCtrl.clear();
      _query = '';
    });
    _reload();
  }

  void _toggle(Customer c) {
    if (c.optedOut) return;
    setState(() {
      if (!_selected.add(c.id)) _selected.remove(c.id);
    });
  }

  /// Select every matching, messageable customer — across all pages, not just
  /// the loaded ones — or clear the selection when it already covers them.
  Future<void> _toggleAll() async {
    if (_selected.isNotEmpty && _selected.length >= _totalEligible) {
      setState(_selected.clear);
      return;
    }
    setState(() => _selectingAll = true);
    try {
      final ids = await widget.loadIds(_params);
      if (!mounted) return;
      setState(() => _selected.addAll(ids));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sanitizeUiErrorMessage(e)),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  /// Every customer matching the current search/filters/sort — all pages, not
  /// just the loaded ones — as Excel or PDF, downloaded or shared.
  Future<void> _export() async {
    final choice = await pickExport(context);
    if (choice == null || !mounted) return;
    final (format, action) = choice;
    setState(() => _exporting = true);
    try {
      final all = <Customer>[];
      while (true) {
        final r = await widget.loadCustomers(
            {..._params, 'offset': '${all.length}', 'limit': '$_exportPageSize'});
        final page = _parse(r);
        all.addAll(page);
        final total = (r['total'] as num?)?.toInt() ?? all.length;
        if (page.isEmpty || all.length >= total) break;
      }
      final pdf = format == ExportFormat.pdf;
      final bytes = pdf
          ? await CustomerExport.customersPdf(all,
              businessName: ref.read(businessNameProvider))
          : CustomerExport.customersXlsx(all);
      if (!mounted) return;
      await deliverExport(
        context,
        action,
        bytes,
        'Customers-${_fileDate()}.${pdf ? 'pdf' : 'xlsx'}',
        pdf ? CustomerExport.pdfMime : CustomerExport.xlsxMime,
      );
    } catch (e) {
      if (mounted) _exportFailed(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openFilters() async {
    final picked = await showModalBottomSheet<CustomerFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(
        initial: _filter,
        // Live "Show N customers": counts only (limit=0) for the draft.
        countFor: (f) async {
          final r = await widget.loadCustomers({
            ...customerListParams(query: _query, filter: f),
            'limit': '0',
          });
          return (r['total'] as num?)?.toInt() ?? 0;
        },
      ),
    );
    if (picked != null && mounted) _setFilter(picked);
  }

  Future<void> _openCustomer(Customer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerBillsScreen(
          customer: c,
          // Opt-out changed there: update this row in place instead of
          // reloading the list and losing the scroll position.
          onChanged: (updated) {
            if (!mounted) return;
            setState(() {
              _items = [
                for (final x in _items) x.id == updated.id ? updated : x
              ];
              if (updated.optedOut) {
                _selected.remove(updated.id);
                _totalEligible = (_totalEligible - 1).clamp(0, _total);
              } else {
                _totalEligible = (_totalEligible + 1).clamp(0, _total);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _compose() async {
    final ids = _selected.toList();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComposeSheet(
        customerIds: ids,
        shopName: ref.read(businessNameProvider),
      ),
    );
    if (sent == true && mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The search/filter bar stays up while a query returns nothing, so the
    // owner can always undo it; it is hidden only when the shop truly has no
    // customers yet.
    final showControls = _error == null && !(_loading && _items.isEmpty) &&
        _totalAll > 0;

    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          title: Text(l10n.customersTitle),
          actions: [
            if (_totalAll > 0)
              _ExportButton(busy: _exporting, onPressed: _export),
          ],
        ),
        if (showControls) ...[
          _buildToolbar(l10n),
          const SizedBox(height: AppSpacing.space8),
          if (_filter.activeCount > 0) _buildActiveChips(l10n),
          _buildResultLine(l10n),
          // Same 2px either way, so the list never jumps when it appears.
          SizedBox(
            height: 2,
            child: _refreshing
                ? const LinearProgressIndicator(minHeight: 2)
                : const Divider(height: 2, thickness: 1),
          ),
        ],
        Expanded(child: _buildBody(l10n)),
        if (_selected.isNotEmpty) _buildActionBar(l10n),
      ]),
    );
  }

  /// Search · Filters (with active count) · Sort.
  Widget _buildToolbar(AppLocalizations l10n) {
    final count = _filter.activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.space12, AppSpacing.space12, AppSpacing.space12, 0),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.customersSearchHint,
                isDense: true,
                prefixIcon: const Icon(Icons.search_outlined,
                    size: 18, color: AppColors.textSecondary),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space16, vertical: 0),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space8),
        Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: IconButton.outlined(
            tooltip: l10n.customersFilters,
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<Object>(
          tooltip: l10n.customersSortBy,
          icon: const Icon(Icons.swap_vert),
          onSelected: (v) {
            if (v is CustomerSort) {
              // Picking the current field again flips the direction; a new
              // field starts with its natural order (names A→Z, numbers high→low).
              _setSort(v, v == _sort ? !_descending : v != CustomerSort.name);
            } else if (v is bool) {
              _setSort(_sort, v);
            }
          },
          itemBuilder: (_) => [
            for (final s in CustomerSort.values)
              CheckedPopupMenuItem<Object>(
                value: s,
                checked: s == _sort,
                child: Text(_sortLabel(l10n, s)),
              ),
            const PopupMenuDivider(),
            // Direction, worded for the field picked above.
            CheckedPopupMenuItem<Object>(
              value: true,
              checked: _descending,
              child: Text(switch (_sort) {
                CustomerSort.spend => l10n.customersSortHighLow,
                CustomerSort.visits => l10n.customersSortMostVisits,
                CustomerSort.recent => l10n.customersSortNewest,
                CustomerSort.name => l10n.customersSortZA,
              }),
            ),
            CheckedPopupMenuItem<Object>(
              value: false,
              checked: !_descending,
              child: Text(switch (_sort) {
                CustomerSort.spend => l10n.customersSortLowHigh,
                CustomerSort.visits => l10n.customersSortFewestVisits,
                CustomerSort.recent => l10n.customersSortOldest,
                CustomerSort.name => l10n.customersSortAZ,
              }),
            ),
          ],
        ),
      ]),
    );
  }

  /// What is currently narrowing the list — each removable on its own.
  Widget _buildActiveChips(AppLocalizations l10n) {
    final f = _filter;
    final chips = <Widget>[
      if (f.minVisits != null || f.maxVisits != null)
        _activeChip(
          l10n.customersChipVisits(
              _range<int>(f.minVisits, f.maxVisits, (v) => '$v')),
          () => _setFilter(CustomerFilter(
              minSpend: f.minSpend, maxSpend: f.maxSpend,
              recency: f.recency, offers: f.offers)),
        ),
      if (f.minSpend != null || f.maxSpend != null)
        _activeChip(
          l10n.customersChipSpend(
              _range<double>(f.minSpend, f.maxSpend, _money)),
          () => _setFilter(CustomerFilter(
              minVisits: f.minVisits, maxVisits: f.maxVisits,
              recency: f.recency, offers: f.offers)),
        ),
      if (f.recency != CustomerRecency.any)
        _activeChip(
          _recencyLabel(l10n, f.recency),
          () => _setFilter(CustomerFilter(
              minVisits: f.minVisits, maxVisits: f.maxVisits,
              minSpend: f.minSpend, maxSpend: f.maxSpend, offers: f.offers)),
        ),
      if (f.offers != CustomerOffers.all)
        _activeChip(
          f.offers == CustomerOffers.allowed
              ? l10n.customersOffersAllowed
              : l10n.customersOffersOptedOut,
          () => _setFilter(CustomerFilter(
              minVisits: f.minVisits, maxVisits: f.maxVisits,
              minSpend: f.minSpend, maxSpend: f.maxSpend,
              recency: f.recency)),
        ),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space12),
        children: [
          ...chips,
          TextButton(
            onPressed: () => _setFilter(CustomerFilter.none),
            style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
            child: Text(l10n.customersClearAll),
          ),
        ],
      ),
    );
  }

  Widget _activeChip(String label, VoidCallback onRemove) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.space8),
        child: InputChip(
          label: Text(label),
          labelStyle: const TextStyle(color: AppColors.textPrimary),
          onDeleted: onRemove,
          onPressed: _openFilters,
          visualDensity: VisualDensity.compact,
          backgroundColor: AppColors.primaryLight,
          side: BorderSide.none,
        ),
      );

  /// "12 of 40 customers" + select-all for every match across all pages.
  Widget _buildResultLine(AppLocalizations l10n) {
    final allSelected =
        _selected.isNotEmpty && _selected.length >= _totalEligible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.space16, 0, AppSpacing.space8, AppSpacing.space4),
      child: Row(children: [
        Expanded(
          child: Text(
            l10n.customersResultCount(_total, _totalAll),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        if (_selectingAll)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.space8),
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_totalEligible > 0)
          TextButton(
            onPressed: _toggleAll,
            style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
            child: Text(allSelected
                ? l10n.commonClear
                : l10n.customersSelectAllCount(_totalEligible)),
          ),
      ]),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading && _items.isEmpty) {
      return const CustomersSkeleton();
    }
    if (_error != null) return AppErrorWidget(error: _error!, onRetry: _reload);
    if (_totalAll == 0) {
      return _Empty(icon: Icons.people_outline, text: l10n.customersEmpty);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: _items.isEmpty
          ? ListView(children: [
              const SizedBox(height: 80),
              Center(
                child: Column(children: [
                  Text(l10n.customersNoMatches,
                      style: const TextStyle(color: AppColors.textPrimary)),
                  if (_filter.activeCount > 0 || _query.isNotEmpty)
                    TextButton(
                      onPressed: _clearSearchAndFilters,
                      style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                      child: Text(l10n.customersClearAll),
                    ),
                ]),
              ),
            ])
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.space12),
              // One extra slot at the end for the "loading more" spinner.
              itemCount: _items.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.space8),
              itemBuilder: (context, i) {
                // Next page on its way: shimmer rows, same shape as the real ones.
                if (i >= _items.length) {
                  return const SkeletonWrapper(child: CustomerRowSkeleton());
                }
                final c = _items[i];
                return _CustomerRow(
                  customer: c,
                  selected: _selected.contains(c.id),
                  onToggle: () => _toggle(c),
                  onOpen: () => _openCustomer(c),
                );
              },
            ),
    );
  }

  Widget _buildActionBar(AppLocalizations l10n) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Row(children: [
            Expanded(
              child: Text(
                l10n.customersSelected(_selected.length),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _compose,
              icon: const Icon(Icons.arrow_forward),
              label: Text(l10n.customersNext),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                // The theme's minimumSize is infinitely wide; inside a Row
                // that fails layout and blanks the whole screen.
                minimumSize: const Size(0, 44),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The full filter panel. Edits a draft; the button shows how many customers
/// it will leave and applies it. Pops the new [CustomerFilter].
class _FilterSheet extends StatefulWidget {
  final CustomerFilter initial;

  /// How many customers the draft would show — asked of the server.
  final Future<int> Function(CustomerFilter) countFor;

  const _FilterSheet({required this.initial, required this.countFor});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _minVisits = TextEditingController(text: _s(widget.initial.minVisits));
  late final _maxVisits = TextEditingController(text: _s(widget.initial.maxVisits));
  late final _minSpend = TextEditingController(text: _s(widget.initial.minSpend));
  late final _maxSpend = TextEditingController(text: _s(widget.initial.maxSpend));
  late CustomerRecency _recency = widget.initial.recency;
  late CustomerOffers _offers = widget.initial.offers;

  /// Chip labels in plain black, selected or not.
  static const _chipText = TextStyle(color: AppColors.textPrimary);

  static String _s(num? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  // Live "Show N customers": null while (re)counting. Debounced so typing a
  // number is one request, and sequenced so a slow reply cannot overwrite a
  // newer count.
  int? _count;
  Timer? _countDebounce;
  int _countSeq = 0;

  @override
  void initState() {
    super.initState();
    _recount();
  }

  @override
  void dispose() {
    _countDebounce?.cancel();
    for (final c in [_minVisits, _maxVisits, _minSpend, _maxSpend]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rebuild with the new draft and count it shortly after the last change.
  void _changed([VoidCallback? edit]) {
    setState(() {
      edit?.call();
      _count = null;
    });
    _countDebounce?.cancel();
    _countDebounce = Timer(const Duration(milliseconds: 300), _recount);
  }

  Future<void> _recount() async {
    final seq = ++_countSeq;
    try {
      final n = await widget.countFor(_draft);
      if (mounted && seq == _countSeq) setState(() => _count = n);
    } catch (_) {
      // No count is fine — the button still applies the filter.
    }
  }

  /// The draft as a filter. A min above its max is read as the range the user
  /// meant (swapped), never as "match nothing".
  CustomerFilter get _draft {
    int? i(TextEditingController c) => int.tryParse(c.text.trim());
    double? d(TextEditingController c) => double.tryParse(c.text.trim());
    var (minV, maxV) = (i(_minVisits), i(_maxVisits));
    if (minV != null && maxV != null && minV > maxV) (minV, maxV) = (maxV, minV);
    var (minS, maxS) = (d(_minSpend), d(_maxSpend));
    if (minS != null && maxS != null && minS > maxS) (minS, maxS) = (maxS, minS);
    return CustomerFilter(
      minVisits: minV,
      maxVisits: maxV,
      minSpend: minS,
      maxSpend: maxS,
      recency: _recency,
      offers: _offers,
    );
  }

  void _reset() => _changed(() {
        for (final c in [_minVisits, _maxVisits, _minSpend, _maxSpend]) {
          c.clear();
        }
        _recency = CustomerRecency.any;
        _offers = CustomerOffers.all;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.space8),
              child,
            ],
          ),
        );

    Widget rangeFields(TextEditingController min, TextEditingController max,
            {required bool decimal, String? prefix}) =>
        Row(children: [
          for (final (ctrl, hint) in [
            (min, l10n.customersFilterMin),
            (max, l10n.customersFilterMax),
          ]) ...[
            if (ctrl == max) const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.numberWithOptions(decimal: decimal),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(decimal ? r'[0-9.]' : r'[0-9]')),
                ],
                decoration: InputDecoration(
                  hintText: hint,
                  prefixText: prefix,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _changed(),
              ),
            ),
          ],
        ]);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.space16, AppSpacing.space12, AppSpacing.space8, 0),
          child: Row(children: [
            Expanded(
              child: Text(l10n.customersFilters,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: _reset,
              style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
              child: Text(l10n.customersFilterReset),
            ),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section(l10n.customersFilterVisits,
                    rangeFields(_minVisits, _maxVisits, decimal: false)),
                section(l10n.customersFilterSpend,
                    rangeFields(_minSpend, _maxSpend,
                        decimal: true, prefix: '₹ ')),
                section(
                  l10n.customersFilterLastVisit,
                  Wrap(
                    spacing: AppSpacing.space8,
                    runSpacing: AppSpacing.space8,
                    children: [
                      for (final r in CustomerRecency.values)
                        ChoiceChip(
                          label: Text(_recencyLabel(l10n, r)),
                          labelStyle: _chipText,
                          selected: _recency == r,
                          onSelected: (_) => _changed(() => _recency = r),
                        ),
                    ],
                  ),
                ),
                section(
                  l10n.customersFilterOffers,
                  Wrap(
                    spacing: AppSpacing.space8,
                    children: [
                      for (final (o, label) in [
                        (CustomerOffers.all, l10n.customersOffersAll),
                        (CustomerOffers.allowed, l10n.customersOffersAllowed),
                        (CustomerOffers.optedOut, l10n.customersOffersOptedOut),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          labelStyle: _chipText,
                          selected: _offers == o,
                          onSelected: (_) => _changed(() => _offers = o),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space12),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _draft),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(_count == null
                  ? l10n.customersApply
                  : l10n.customersShowResults(_count!)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final Customer customer;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  const _CustomerRow({
    required this.customer,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = customer;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space8, vertical: AppSpacing.space12),
          child: Row(children: [
            // Opted-out customers are shown but cannot be messaged.
            Checkbox(
              value: selected,
              onChanged: c.optedOut ? null : (_) => onToggle(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (c.optedOut) ...[
                      const SizedBox(width: 6),
                      _Tag(l10n.customersOptedOut),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (c.displayName != c.phone) c.phone,
                      if (c.lastVisit != null)
                        l10n.customersLastVisit(
                            _dateFmt.format(c.lastVisit!.toLocal())),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${c.totalSpend.toStringAsFixed(2)}',
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(l10n.customersBills(c.billCount),
                  style: textTheme.labelSmall
                      ?.copyWith(color: AppColors.textPrimary)),
            ]),
            const Icon(Icons.chevron_right, color: AppColors.textDisabled),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.space16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary)),
          ]),
        ),
      );
}

/// Type one message and send it to every selected customer. Pops `true` once
/// the server has queued it.
class _ComposeSheet extends StatefulWidget {
  final List<String> customerIds;
  final String shopName;

  const _ComposeSheet({required this.customerIds, required this.shopName});

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = context.l10n;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await sendCustomerMessage(widget.customerIds, text);
      if (!mounted) return;
      Navigator.pop(context, true);
      final queued = (r['queued'] as num?)?.toInt() ?? 0;
      final skipped = (r['skipped'] as num?)?.toInt() ?? 0;
      messenger.showSnackBar(SnackBar(
        content: Text(r['will_deliver'] == false
            ? l10n.customersNotDelivering
            : l10n.customersSending(queued, skipped)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: Text(sanitizeUiErrorMessage(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.space16,
        right: AppSpacing.space16,
        top: AppSpacing.space16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.customersComposeTitle(widget.customerIds.length),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.space12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: l10n.customersComposeHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          // What the customer actually receives — the approved template wraps
          // the text with the shop's name.
          Text(
            l10n.customersComposePreview(widget.shopName),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space12),
          ElevatedButton.icon(
            onPressed:
                _sending || _ctrl.text.trim().isEmpty ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(l10n.customersSend),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space12),
            ),
          ),
        ],
      ),
    );
  }
}

/// One customer: totals, the offers on/off switch, and their bills. Tapping a
/// bill opens the same popup History uses.
class CustomerBillsScreen extends ConsumerStatefulWidget {
  final Customer customer;

  /// One page of the customer's bills — { items, total }; defaults to the
  /// API. Tests pass a fake.
  final Future<Map<String, dynamic>> Function(String customerId,
      {int offset, int limit}) loadBills;

  /// Called after the owner changes Stop/Allow offers, so the list behind can
  /// update that row without reloading.
  final ValueChanged<Customer>? onChanged;

  const CustomerBillsScreen({
    super.key,
    required this.customer,
    this.loadBills = getCustomerBills,
    this.onChanged,
  });

  @override
  ConsumerState<CustomerBillsScreen> createState() =>
      _CustomerBillsScreenState();
}

class _CustomerBillsScreenState extends ConsumerState<CustomerBillsScreen> {
  static const _pageSize = 20;

  late Customer _customer = widget.customer;
  List<Bill> _bills = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _savingOptOut = false;
  bool _exporting = false;
  final _scroll = ScrollController();

  bool get _hasMore => _bills.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static List<Bill> _parse(Map<String, dynamic> r) => (r['items'] as List)
      .map((j) => Bill.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();

  /// First page (also pull-to-refresh, and after a bill is voided).
  Future<void> _load() async {
    setState(() {
      _loading = _bills.isEmpty;
      _error = null;
    });
    try {
      final r = await widget.loadBills(_customer.id, offset: 0, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _bills = _parse(r);
        _total = (r['total'] as num?)?.toInt() ?? _bills.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// Next page, appended as the list nears its end.
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    setState(() => _loadingMore = true);
    try {
      final r = await widget.loadBills(_customer.id,
          offset: _bills.length, limit: _pageSize);
      if (!mounted) return;
      final seen = _bills.map((b) => b.id).toSet();
      setState(() {
        _bills = [..._bills, ..._parse(r).where((b) => !seen.contains(b.id))];
        _total = (r['total'] as num?)?.toInt() ?? _total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sanitizeUiErrorMessage(e)),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleOptOut() async {
    final next = !_customer.optedOut;
    setState(() => _savingOptOut = true);
    try {
      await setCustomerOptOut(_customer.id, next);
      if (!mounted) return;
      setState(() => _customer = _customer.copyWith(optedOut: next));
      widget.onChanged?.call(_customer);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sanitizeUiErrorMessage(e)),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _savingOptOut = false);
    }
  }

  /// All of this customer's bills — not just the loaded pages — as Excel or
  /// PDF, downloaded or shared.
  Future<void> _export() async {
    final choice = await pickExport(context);
    if (choice == null || !mounted) return;
    final (format, action) = choice;
    setState(() => _exporting = true);
    try {
      final all = <Bill>[];
      while (true) {
        final r = await widget.loadBills(_customer.id,
            offset: all.length, limit: _exportPageSize);
        final page = _parse(r);
        all.addAll(page);
        final total = (r['total'] as num?)?.toInt() ?? all.length;
        if (page.isEmpty || all.length >= total) break;
      }
      final pdf = format == ExportFormat.pdf;
      final bytes = pdf
          ? await CustomerExport.billsPdf(_customer, all,
              businessName: ref.read(businessNameProvider))
          : CustomerExport.billsXlsx(_customer, all);
      if (!mounted) return;
      final who = CustomerExport.fileSafe(_customer.displayName);
      await deliverExport(
        context,
        action,
        bytes,
        '$who-Bills-${_fileDate()}.${pdf ? 'pdf' : 'xlsx'}',
        pdf ? CustomerExport.pdfMime : CustomerExport.xlsxMime,
      );
    } catch (e) {
      if (mounted) _exportFailed(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openBill(Bill bill) {
    showDialog(
      context: context,
      builder: (_) => BillDetailDialog(
        bill: bill,
        userRole: ref.read(userRoleProvider),
        businessName: ref.read(businessNameProvider),
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = _customer;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          title: Text(c.displayName),
          actions: [
            _ExportButton(
              busy: _exporting,
              onPressed: _loading || _total == 0 ? null : _export,
            ),
          ],
        ),
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.all(AppSpacing.space16),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.phone, style: textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.customersBills(c.billCount)} · ₹${c.totalSpend.toStringAsFixed(2)}',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (c.optedOut)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(l10n.customersOptedOutNote,
                          style: textTheme.bodySmall
                              ?.copyWith(color: AppColors.textPrimary)),
                    ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _savingOptOut ? null : _toggleOptOut,
              icon: Icon(c.optedOut
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined),
              label: Text(c.optedOut
                  ? l10n.customersAllowOffers
                  : l10n.customersStopOffers),
              // Theme minimumSize is infinitely wide — in this Row it blanked
              // the whole page.
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBills(l10n)),
      ]),
    );
  }

  Widget _buildBills(AppLocalizations l10n) {
    if (_loading) return const CustomerBillsSkeleton();
    if (_error != null) return AppErrorWidget(error: _error!, onRetry: _load);
    if (_bills.isEmpty) {
      return _Empty(icon: Icons.receipt_long_outlined, text: l10n.customersNoBills);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.space12),
        // One extra slot at the end for the "loading more" spinner.
        itemCount: _bills.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
        itemBuilder: (context, i) {
          if (i >= _bills.length) {
            return const SkeletonWrapper(child: BillRowSkeleton());
          }
          final bill = _bills[i];
          final itemCount =
              bill.items.fold<double>(0, (s, it) => s + it.quantity);
          return Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ListTile(
              onTap: () => _openBill(bill),
              title: Text(bill.billNumber,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${_dateFmt.format(bill.createdAt.toLocal())} · '
                '${l10n.openOrdersItemCount(itemCount.toInt())} · '
                '${bill.paymentMode.toUpperCase()}',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              trailing: Text('₹${bill.grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          );
        },
      ),
    );
  }
}
