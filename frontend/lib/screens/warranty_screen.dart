import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart' as api;
import '../api.dart' show sanitizeUiErrorMessage;
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../utils/text_formatters.dart' show isIndianMobile;
import '../widgets/app_widgets.dart';
import '../widgets/bottom_nav_bar.dart' show AppBottomNavBar, HidesWithNavBar;
import '../widgets/shell_app_bar.dart';
import '../widgets/warranty_extra_fields_editor.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

enum _WarrantyStatusFilter { all, active, expiringSoon, expired }

extension on _WarrantyStatusFilter {
  String? get apiValue => switch (this) {
        _WarrantyStatusFilter.all => null,
        _WarrantyStatusFilter.active => 'active',
        _WarrantyStatusFilter.expiringSoon => 'expiring_30',
        _WarrantyStatusFilter.expired => 'expired',
      };
}

/// Tyre/battery/electronics shops ("Retail & Warranty" business type): record
/// and look up warranty info for a sold product, by customer phone or serial
/// number. See routes/warranties.js.
class WarrantyScreen extends ConsumerStatefulWidget {
  const WarrantyScreen({super.key});

  @override
  ConsumerState<WarrantyScreen> createState() => _WarrantyScreenState();
}

class _WarrantyScreenState extends ConsumerState<WarrantyScreen> {
  static const _pageSize = 30;

  List<Warranty> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _requestSeq = 0;

  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  _WarrantyStatusFilter _filter = _WarrantyStatusFilter.all;
  /// Purchase-date range filter — independent of [_filter] (expiry-based),
  /// so a shop can e.g. find everything sold last month regardless of
  /// whether it's since expired.
  DateTimeRange? _dateRange;

  late final ProviderSubscription<int> _refreshSignalSub;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    // This screen is kept alive off-screen in the shell's IndexedStack, so a
    // bill finalized while another tab is active still reaches it — not just
    // while the Warranty tab happens to be the visible one.
    _refreshSignalSub =
        ref.listenManual(warrantyRefreshSignalProvider, (prev, next) {
      if (prev != next) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    _refreshSignalSub.close();
    super.dispose();
  }

  Map<String, String> get _params => {
        if (_query.trim().isNotEmpty) 'q': _query.trim(),
        if (_filter.apiValue != null) 'status': _filter.apiValue!,
        if (_dateRange != null)
          'from': DateFormat('yyyy-MM-dd').format(_dateRange!.start),
        if (_dateRange != null)
          'to': DateFormat('yyyy-MM-dd').format(_dateRange!.end),
      };

  Future<void> _reload() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await api.getWarranties(
          {..._params, 'offset': '0', 'limit': '$_pageSize'});
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _total = (r['total'] as num?)?.toInt() ?? 0;
        _items = _parse(r);
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final r = await api.getWarranties(
          {..._params, 'offset': '${_items.length}', 'limit': '$_pageSize'});
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _total = (r['total'] as num?)?.toInt() ?? 0;
        final seen = _items.map((w) => w.id).toSet();
        _items = [..._items, ..._parse(r).where((w) => !seen.contains(w.id))];
      });
    } catch (_) {
      // Keep the current page; the next scroll/retry tries again.
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loadingMore = false);
    }
  }

  static List<Warranty> _parse(Map<String, dynamic> r) => (r['items'] as List)
      .map((j) => Warranty.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();

  void _onSearchChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  void _setFilter(_WarrantyStatusFilter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    _reload();
  }

  bool get _hasActiveFilters =>
      _filter != _WarrantyStatusFilter.all ||
      _query.trim().isNotEmpty ||
      _dateRange != null;

  void _clearAllFilters() {
    setState(() {
      _filter = _WarrantyStatusFilter.all;
      _query = '';
      _searchCtrl.clear();
      _dateRange = null;
    });
    _reload();
  }

  /// Picks the empty-state icon/message for the current filter combination —
  /// search takes priority (it's the most specific thing the user did),
  /// then the date range, then the status filter, falling back to the
  /// true "nothing here yet" state only when nothing is filtered at all.
  (IconData, String) _emptyStateContent(AppLocalizations l10n) {
    if (_query.trim().isNotEmpty) {
      return (Icons.search_off_outlined, l10n.warrantyEmptySearch(_query.trim()));
    }
    if (_dateRange != null && _filter == _WarrantyStatusFilter.all) {
      return (Icons.event_busy_outlined, l10n.warrantyEmptyDateRange);
    }
    return switch (_filter) {
      _WarrantyStatusFilter.active =>
        (Icons.verified_outlined, l10n.warrantyEmptyActive),
      _WarrantyStatusFilter.expiringSoon =>
        (Icons.hourglass_empty_outlined, l10n.warrantyEmptyExpiringSoon),
      _WarrantyStatusFilter.expired =>
        (Icons.history_toggle_off_outlined, l10n.warrantyEmptyExpired),
      _WarrantyStatusFilter.all =>
        (Icons.verified_user_outlined, l10n.warrantyEmptyState),
    };
  }

  Future<void> _showDateFilterSheet() async {
    final l10n = context.l10n;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DateFilterSheet(
        l10n: l10n,
        initialRange: _dateRange,
        onApply: (range) {
          setState(() => _dateRange = range);
          _reload();
        },
        onClear: () {
          setState(() => _dateRange = null);
          _reload();
        },
      ),
    );
  }

  Future<void> _openForm({Warranty? existing}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WarrantyFormScreen(existing: existing)),
    );
    if (saved == true) _reload();
  }

  /// Tapping a row shows its details first (read-only) — the record might
  /// just be a lookup ("is this still under warranty?"), so jumping straight
  /// into an editable form was more than most taps needed. Edit is one tap
  /// away from there.
  Future<void> _showDetail(Warranty w) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (_) => WarrantyDetailDialog(warranty: w),
    );
    if (edit == true) await _openForm(existing: w);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: Column(children: [
        ShellAppBar(title: Text(l10n.warrantyTitle)),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.warrantySearchHint,
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_outlined,
                          size: 18, color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space16, vertical: 0),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              // Purchase-date filter — a dedicated icon rather than another
              // horizontal-scroll chip, since picking a range needs its own
              // sheet (two taps: open, then pick) rather than the one-tap
              // toggle the status chips below are.
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: _dateRange != null
                      ? AppColors.primary
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(
                      color: _dateRange != null
                          ? AppColors.primary
                          : AppColors.border),
                ),
                child: IconButton(
                  tooltip: l10n.warrantyFilterDate,
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.calendar_today_outlined,
                      size: 18,
                      color: _dateRange != null
                          ? Colors.white
                          : AppColors.textSecondary),
                  onPressed: _showDateFilterSheet,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space16),
            children: [
              _FilterChip(
                label: l10n.warrantyFilterAll,
                selected: _filter == _WarrantyStatusFilter.all,
                onTap: () => _setFilter(_WarrantyStatusFilter.all),
              ),
              _FilterChip(
                label: l10n.warrantyFilterActive,
                selected: _filter == _WarrantyStatusFilter.active,
                onTap: () => _setFilter(_WarrantyStatusFilter.active),
              ),
              _FilterChip(
                label: l10n.warrantyFilterExpiringSoon,
                selected: _filter == _WarrantyStatusFilter.expiringSoon,
                onTap: () => _setFilter(_WarrantyStatusFilter.expiringSoon),
              ),
              _FilterChip(
                label: l10n.warrantyFilterExpired,
                selected: _filter == _WarrantyStatusFilter.expired,
                onTap: () => _setFilter(_WarrantyStatusFilter.expired),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        Expanded(child: _buildBody(l10n)),
      ]),
      floatingActionButton: HidesWithNavBar(
        // Lifted clear of the floating glass nav bar, and dropped out of
        // sight along with it when scrolling hides the bar (2 = its own
        // height plus the bottom margin, so it fully clears the edge) —
        // same fix as the Items tab's FAB (items_screen.dart).
        drop: 2,
        child: Padding(
          padding: EdgeInsets.only(bottom: AppBottomNavBar.fabLift(context)),
          child: FloatingActionButton(
            heroTag: 'addWarrantyFab',
            onPressed: () => _openForm(),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(dynamic l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(sanitizeUiErrorMessage(_error)),
          const SizedBox(height: AppSpacing.space8),
          OutlinedButton(
            onPressed: _reload,
            // Theme default minimumSize is full-width (double.infinity);
            // inside a Center/Column it only gets loose width constraints,
            // which crashes layout unless overridden — see the "Pick item"
            // button above for the same fix.
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(l10n.commonRetry),
          ),
        ]),
      );
    }
    // A freshly finalized bill's warranty record is created in the background
    // (autoCreateWarranties in routes/bills.js is fire-and-forget, so the
    // sale doesn't wait on it) — pulling down lets staff re-check a moment
    // later instead of force-closing and reopening the tab.
    if (_items.isEmpty) {
      final (icon, message) = _emptyStateContent(l10n);
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space24),
          children: [
            const SizedBox(height: 64),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 48, color: AppColors.textDisabled),
                const SizedBox(height: AppSpacing.space16),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textPrimary)),
                if (_hasActiveFilters) ...[
                  const SizedBox(height: AppSpacing.space16),
                  OutlinedButton(
                    onPressed: _clearAllFilters,
                    // Theme default minimumSize is full-width; inside a
                    // Center/Column it only gets loose width constraints,
                    // which crashes layout unless overridden — see the
                    // "Pick item"/Retry buttons above for the same fix.
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: Text(l10n.warrantyClearFilters),
                  ),
                ],
              ]),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
            AppSpacing.space16, AppSpacing.space16),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.space16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final w = _items[i];
          return _WarrantyRow(
            warranty: w,
            onTap: () => _showDetail(w),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.space8),
      child: ChoiceChip(
        label: Text(
          label,
          style: AppFont.style(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// Bottom sheet for the purchase-date filter: a "From"/"To" field pair, each
/// opening a plain single-date picker, plus Clear/Apply actions — simpler
/// than embedding a range calendar, and consistent with this app's other
/// bottom-sheet forms (e.g. expenses_screen.dart's add-expense sheet: a drag
/// handle, title, rounded-top surface card).
class _DateFilterSheet extends StatefulWidget {
  final AppLocalizations l10n;
  final DateTimeRange? initialRange;
  final void Function(DateTimeRange range) onApply;
  final VoidCallback onClear;

  const _DateFilterSheet({
    required this.l10n,
    required this.initialRange,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends State<_DateFilterSheet> {
  static final _fieldFmt = DateFormat('dd MMM yyyy');

  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.initialRange?.start;
    _to = widget.initialRange?.end;
  }

  Future<void> _pick(bool isFrom) async {
    final now = DateTime.now();
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: now,
      initialDate: initial.isAfter(now) ? now : initial,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(_from!)) _to = _from;
      } else {
        _to = picked;
        if (_from != null && _from!.isAfter(_to!)) _from = _to;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canApply = _from != null && _to != null;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text(l10n.warrantyFilterDate,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: _DateFieldButton(
                label: l10n.warrantyFilterDateFrom,
                date: _from,
                formatter: _fieldFmt,
                onTap: () => _pick(true),
              ),
            ),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: _DateFieldButton(
                label: l10n.warrantyFilterDateTo,
                date: _to,
                formatter: _fieldFmt,
                onTap: () => _pick(false),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onClear();
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(l10n.commonClear),
              ),
            ),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: ElevatedButton(
                onPressed: canApply
                    ? () {
                        Navigator.pop(context);
                        widget.onApply(DateTimeRange(start: _from!, end: _to!));
                      }
                    : null,
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(l10n.warrantyFilterDateApply),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DateFieldButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final DateFormat formatter;
  final VoidCallback onTap;

  const _DateFieldButton({
    required this.label,
    required this.date,
    required this.formatter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          date != null ? formatter.format(date!) : '—',
          style: TextStyle(
              color: date != null ? AppColors.textPrimary : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _WarrantyRow extends StatelessWidget {
  final Warranty warranty;
  final VoidCallback onTap;
  const _WarrantyRow({required this.warranty, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final w = warranty;
    final textTheme = Theme.of(context).textTheme;
    final (statusLabel, statusColor) = w.isExpired
        ? (l10n.warrantyFilterExpired, AppColors.error)
        : w.isExpiringSoon
            ? (l10n.warrantyFilterExpiringSoon, AppColors.warning)
            : (l10n.warrantyFilterActive, AppColors.success);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title shares its row with the status badge (not the whole
              // card) — on a narrow phone the badge only ever competes with
              // the short item name for width, never with the longer
              // customer/serial/extra-data line below.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(w.itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(statusLabel,
                        style: textTheme.labelSmall?.copyWith(
                            color: statusColor, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  w.displayName,
                  if (w.serialNumber?.isNotEmpty ?? false) w.serialNumber!,
                  // So a match on an extra detail (e.g. a vehicle number
                  // typed into the "KM Reading"/"Vehicle Number" fields)
                  // is visible in the result, not just a silent hit.
                  for (final e in w.extraData)
                    if (e.value.isNotEmpty) '${e.label}: ${e.value}',
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    l10n.warrantyExpiresOn(_dateFmt.format(w.expiryDate)),
                    style: textTheme.labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only detail view — shown on tap, before committing to editing.
// ---------------------------------------------------------------------------

/// Shows one warranty record read-only, with an Edit action — rather than
/// jumping straight into an editable form on every tap, when most taps are
/// just "is this still under warranty?" lookups. Pops `true` when the user
/// chooses Edit, so the caller can then push [WarrantyFormScreen].
class WarrantyDetailDialog extends StatelessWidget {
  final Warranty warranty;
  const WarrantyDetailDialog({super.key, required this.warranty});

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.space8),
          Expanded(
            flex: 3,
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final w = warranty;
    final (statusLabel, statusType) = w.isExpired
        ? (l10n.warrantyFilterExpired, StatusType.error)
        : w.isExpiringSoon
            ? (l10n.warrantyFilterExpiringSoon, StatusType.warning)
            : (l10n.warrantyFilterActive, StatusType.success);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(w.itemName,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.space8),
          StatusBadge(label: statusLabel, status: statusType),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(context, l10n.warrantyCustomerName, w.displayName),
              _row(context, l10n.warrantyCustomerPhone, w.customerPhone),
              if (w.category?.isNotEmpty ?? false)
                _row(context, l10n.warrantyCategory, w.category!),
              if (w.serialNumber?.isNotEmpty ?? false)
                _row(context, l10n.warrantySerialNumber, w.serialNumber!),
              _row(context, l10n.warrantyPurchaseDate,
                  _dateFmt.format(w.purchaseDate)),
              _row(context, l10n.warrantyPeriodMonths, '${w.warrantyMonths}'),
              _row(context, l10n.warrantyExpiryDateLabel,
                  _dateFmt.format(w.expiryDate)),
              if (w.extraData.isNotEmpty) ...[
                const Divider(height: AppSpacing.space24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.warrantyExtraDetails,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: AppSpacing.space4),
                for (final e in w.extraData) _row(context, e.label, e.value),
              ],
              if (w.notes?.isNotEmpty ?? false) ...[
                const Divider(height: AppSpacing.space24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.warrantyNotes,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: AppSpacing.space4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(w.notes!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.commonEdit),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit form
// ---------------------------------------------------------------------------

class WarrantyFormScreen extends ConsumerStatefulWidget {
  final Warranty? existing;
  const WarrantyFormScreen({super.key, this.existing});

  @override
  ConsumerState<WarrantyFormScreen> createState() => _WarrantyFormScreenState();
}

class _WarrantyFormScreenState extends ConsumerState<WarrantyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _monthsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _itemId;
  String? _category;
  DateTime _purchaseDate = DateTime.now();
  final List<WarrantyExtraRow> _extraRows = [];
  bool _saving = false;
  bool _deleting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    if (w != null) {
      _nameCtrl.text = w.customerName ?? '';
      // QR-order phones are stored "91XXXXXXXXXX"; edit the local 10 digits.
      final p = w.customerPhone.replaceAll(RegExp(r'\D'), '');
      _phoneCtrl.text =
          p.length == 12 && p.startsWith('91') ? p.substring(2) : p;
      _productCtrl.text = w.itemName;
      _monthsCtrl.text = '${w.warrantyMonths}';
      _notesCtrl.text = w.notes ?? '';
      _itemId = w.itemId;
      _category = w.category;
      _purchaseDate = w.purchaseDate;
      for (final e in w.extraData) {
        _extraRows.add(WarrantyExtraRow.fromField(e));
      }
    } else {
      _monthsCtrl.text = '12';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _productCtrl.dispose();
    _monthsCtrl.dispose();
    _notesCtrl.dispose();
    for (final r in _extraRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _pickItem() async {
    final items = await ref.read(itemsProvider.future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemPickerSheet(items: items),
    );
    if (picked == null) return;
    setState(() {
      _itemId = picked.id;
      _productCtrl.text = picked.name;
      _category = picked.category;
      if (picked.defaultWarrantyMonths != null) {
        _monthsCtrl.text = '${picked.defaultWarrantyMonths}';
      }
    });
    _applyTemplateForCategory();
  }

  /// Adds a row for every template field of [_category] that isn't already
  /// present, so switching products doesn't wipe values the staff already
  /// typed for a field the two products happen to share.
  void _applyTemplateForCategory() {
    final templates = ref.read(warrantyFieldTemplatesProvider).valueOrNull;
    if (applyWarrantyFieldTemplate(_extraRows, _category, templates)) {
      setState(() {});
    }
  }

  void _addAdHocRow() {
    setState(() => _extraRows.add(WarrantyExtraRow(
          labelCtrl: TextEditingController(),
          valueCtrl: TextEditingController(),
        )));
  }

  void _removeRow(WarrantyExtraRow row) {
    setState(() => _extraRows.remove(row));
    row.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final body = {
      'customer_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      'customer_phone': _phoneCtrl.text.trim(),
      'item_id': _itemId,
      'item_name': _productCtrl.text.trim(),
      'category': _category,
      // No form field for this anymore — staff add it as an ad-hoc "Serial
      // Number" label in extra_data instead. Omitted (not sent as null) so
      // editing an older record that already has one doesn't wipe it.
      'purchase_date': _purchaseDate.toIso8601String().split('T').first,
      'warranty_months': int.tryParse(_monthsCtrl.text.trim()) ?? 0,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'extra_data': warrantyRowsPayload(_extraRows),
    };
    try {
      if (_isEdit) {
        await api.updateWarranty(widget.existing!.id, body);
      } else {
        await api.createWarranty(body);
      }
      rememberWarrantyLabels(adHocWarrantyLabels(_extraRows));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sanitizeUiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.warrantyDeleteConfirmTitle),
        content: Text(l10n.warrantyDeleteConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await api.deleteWarranty(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sanitizeUiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isOwner = ref.watch(userRoleProvider) == 'owner';
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.warrantyEditTitle : l10n.warrantyAddTitle),
        actions: [
          if (_isEdit && isOwner)
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
              onPressed: _deleting ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space16),
          children: [
            AppTextField(
              label: l10n.warrantyCustomerName,
              controller: _nameCtrl,
              capitalizeWords: true,
            ),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantyCustomerPhone,
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.warrantyCustomerPhoneRequired
                  : !isIndianMobile(v)
                      ? l10n.billingPhoneInvalid
                      : null,
            ),
            const SizedBox(height: AppSpacing.space16),
            Row(children: [
              Expanded(
                child: AppTextField(
                  label: l10n.warrantyProduct,
                  controller: _productCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.warrantyProductRequired
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              OutlinedButton(
                onPressed: _pickItem,
                // The app-wide OutlinedButton theme defaults to a
                // full-width minimumSize (for buttons meant to fill their
                // parent); a compact inline button next to a text field
                // must override it, or the Row gives it loose width while
                // its minWidth constraint demands infinity — an invalid
                // combination that crashes layout (same pattern as the
                // Cancel/Confirm buttons in home_screen.dart's dialogs).
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(l10n.warrantyPickItem),
              ),
            ]),
            const SizedBox(height: AppSpacing.space16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(labelText: l10n.warrantyPurchaseDate),
                child: Text(_dateFmt.format(_purchaseDate)),
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantyPeriodMonths,
              controller: _monthsCtrl,
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? l10n.warrantyPeriodInvalid : null;
              },
            ),
            const SizedBox(height: AppSpacing.space24),
            WarrantyExtraFieldsEditor(
              title: l10n.warrantyExtraDetails,
              rows: _extraRows,
              extraSuggestions: allTemplateLabels(
                  ref.watch(warrantyFieldTemplatesProvider).valueOrNull),
              onAddRow: _addAdHocRow,
              onRemoveRow: _removeRow,
            ),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantyNotes,
              controller: _notesCtrl,
            ),
            const SizedBox(height: AppSpacing.space24),
            PrimaryButton(
              text: _saving ? l10n.commonSaving : l10n.commonSave,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemPickerSheet extends StatefulWidget {
  final List<Item> items;
  const _ItemPickerSheet({required this.items});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = widget.items
        .where((i) =>
            _query.trim().isEmpty ||
            i.name.toLowerCase().contains(_query.trim().toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: l10n.warrantyPickItem,
              isDense: true,
              prefixIcon: const Icon(Icons.search_outlined, size: 18),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSpacing.space8),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final item = filtered[i];
                return ListTile(
                  title: Text(item.name),
                  subtitle: item.category != null ? Text(item.category!) : null,
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
