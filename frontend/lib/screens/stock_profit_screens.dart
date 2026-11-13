import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api.dart' as api;
import '../providers.dart';
import '../services/stock_report_export.dart';
import '../theme/app_theme.dart';
import '../widgets/export_sheet.dart';
import '../widgets/shell_app_bar.dart';

final _qtyFmt = NumberFormat('#,##0.###');
final _moneyFmt = NumberFormat('#,##0.00');
final _dayFmt = DateFormat('dd MMM yyyy');
final _shortDayFmt = DateFormat('dd MMM yy');

double _n(Object? v) => v == null ? 0 : double.tryParse(v.toString()) ?? 0;
String _q(Object? v) => _qtyFmt.format(_n(v));
String _m(Object? v) => v == null ? '–' : _moneyFmt.format(_n(v));
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

enum _Preset {
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last3('Last 3 months'),
  last6('Last 6 months'),
  thisFy('This financial year'),
  thisYear('This year'),
  lastYear('Last year'),
  custom('Custom range…');

  final String label;
  const _Preset(this.label);
}

class _Period {
  final _Preset preset;
  final DateTimeRange range;
  const _Period(this.preset, this.range);
}

/// The dates a preset means right now. Never ends after today (no future
/// stock). Months back start on the 1st, so "Last 6 months" is six calendar
/// months including the current one. Financial year is Apr–Mar (India).
_Period _periodFor(_Preset p) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  DateTimeRange r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);
  switch (p) {
    case _Preset.yesterday:
      final y = today.subtract(const Duration(days: 1));
      return _Period(p, r(y, y));
    case _Preset.last7:
      return _Period(p, r(today.subtract(const Duration(days: 6)), today));
    case _Preset.thisMonth:
      return _Period(p, r(DateTime(n.year, n.month, 1), today));
    case _Preset.lastMonth:
      return _Period(p, r(DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 0)));
    case _Preset.last3:
      return _Period(p, r(DateTime(n.year, n.month - 2, 1), today));
    case _Preset.last6:
      return _Period(p, r(DateTime(n.year, n.month - 5, 1), today));
    case _Preset.thisFy:
      return _Period(p, r(DateTime(n.month >= 4 ? n.year : n.year - 1, 4, 1), today));
    case _Preset.thisYear:
      return _Period(p, r(DateTime(n.year, 1, 1), today));
    case _Preset.lastYear:
      return _Period(p, r(DateTime(n.year - 1, 1, 1), DateTime(n.year - 1, 12, 31)));
    case _Preset.today:
    case _Preset.custom:
      return _Period(p == _Preset.custom ? p : _Preset.today, r(today, today));
  }
}

// Each report keeps its own period. Stock opens on today (the daily question
// is "what did I start with and end with today"); profit on the current month.
final stockPeriodProvider =
    StateProvider.autoDispose<_Period>((ref) => _periodFor(_Preset.today));
final profitPeriodProvider =
    StateProvider.autoDispose<_Period>((ref) => _periodFor(_Preset.thisMonth));

final _stockProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final r = ref.watch(stockPeriodProvider).range;
  return api.getStockSummary(from: _iso(r.start), to: _iso(r.end));
});

final _profitProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final r = ref.watch(profitPeriodProvider).range;
  return api.getItemProfit(from: _iso(r.start), to: _iso(r.end));
});

final _stockDailyProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (DateTimeRange, String?, String?)>((ref, k) =>
        api.getStockDaily(
            from: _iso(k.$1.start), to: _iso(k.$1.end), itemId: k.$2, variantId: k.$3));

List<Map<String, dynamic>> _rows(Map<String, dynamic> d) => ((d['rows'] as List?) ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

String _period(DateTimeRange r) => r.start == r.end
    ? _dayFmt.format(r.start)
    // "to", not an en dash: the PDF font cannot draw one (shows a box).
    : '${_dayFmt.format(r.start)} to ${_dayFmt.format(r.end)}';

Future<DateTimeRange?> _pickCustom(BuildContext context, DateTimeRange initial) =>
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );

/// One compact row: period dropdown, the dates it resolves to, and a search
/// icon. The icon turns the whole row into a search field; closing it clears the
/// search and brings the row back. "Custom range…" opens the date picker
/// (cancelling keeps the period); tapping the dates re-opens it.
class _FilterBar extends StatefulWidget {
  final _Period period;
  final void Function(_Period) onChanged;
  final void Function(String) onSearch;
  const _FilterBar(
      {required this.period, required this.onChanged, required this.onSearch});

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  bool _searching = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _custom() async {
    final picked = await _pickCustom(context, widget.period.range);
    if (picked != null) widget.onChanged(_Period(_Preset.custom, picked));
  }

  void _closeSearch() {
    _ctrl.clear();
    widget.onSearch('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: SizedBox(
        height: 38,
        child: _searching
            ? TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search item',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close search',
                    onPressed: _closeSearch,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: widget.onSearch,
              )
            : Row(children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_Preset>(
                      value: period.preset,
                      isDense: true,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      items: [
                        for (final x in _Preset.values)
                          DropdownMenuItem(value: x, child: Text(x.label)),
                      ],
                      onChanged: (x) {
                        if (x == null) return;
                        if (x == _Preset.custom) {
                          _custom();
                        } else {
                          widget.onChanged(_periodFor(x));
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: _custom,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_period(period.range),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search item',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _searching = true),
                ),
              ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spreadsheet-style grid: sticky header, scrolling rows, totals footer.
// Wider than the screen → scrolls sideways as one block (header included).
// ---------------------------------------------------------------------------
class _Col {
  final String label;
  final double width;
  final bool left;
  const _Col(this.label, this.width, {this.left = false});
}

class _Grid extends StatelessWidget {
  final List<_Col> cols;
  final List<List<String>> rows;
  final List<String>? footer;
  final void Function(int row)? onRowTap;
  const _Grid({required this.cols, required this.rows, this.footer, this.onRowTap});

  static final _line = BorderSide(color: Colors.grey.shade300, width: 0.8);

  static const _fs = 12.0;

  // Natural width of a cell's text, so nothing is ever cut off with "…".
  static double _textWidth(String t, bool bold) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(fontSize: _fs, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  /// Each column is at least its declared width, and wide enough for its
  /// longest value (header and totals are bold, so measured bold).
  List<double> _widths() => [
        for (var i = 0; i < cols.length; i++)
          [
            cols[i].width,
            _textWidth(cols[i].label, true) + 14,
            for (final r in rows) _textWidth(r[i], false) + 14,
            if (footer != null) _textWidth(footer![i], true) + 14,
          ].reduce((a, b) => a > b ? a : b),
      ];

  Widget _row(List<String> cells, List<double> w,
      {Color? bg, bool bold = false, bool header = false, VoidCallback? onTap}) {
    final child = Container(
      decoration: BoxDecoration(color: bg, border: Border(bottom: _line)),
      child: Row(children: [
        for (var i = 0; i < cols.length; i++)
          Container(
            width: w[i],
            height: header ? 32 : 30,
            alignment: cols[i].left ? Alignment.centerLeft : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(border: Border(right: _line)),
            child: Text(
              cells[i],
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: _fs,
                fontWeight: bold || header ? FontWeight.w700 : FontWeight.w400,
                // Negative figures stand out, like a spreadsheet's red numbers.
                color: !header && !cols[i].left && cells[i].startsWith('-')
                    ? Colors.red
                    : null,
              ),
            ),
          ),
      ]),
    );
    return onTap == null ? child : InkWell(onTap: onTap, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final base = _widths();
    final total = base.fold<double>(0, (s, c) => s + c);
    return LayoutBuilder(builder: (context, box) {
      // Room to spare → stretch the columns to fill it; too wide → scroll
      // sideways. The -2 leaves space for the table's own left border.
      final scale = box.maxWidth - 2 > total ? (box.maxWidth - 2) / total : 1.0;
      final w = [for (final x in base) x * scale];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total * scale + 2,
          child: Container(
            decoration: BoxDecoration(
                border: Border(top: _line, left: _line), color: Colors.white),
            // min size: the totals row sits right under the last data row, and
            // only reaches the screen bottom when the rows fill the screen.
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _row([for (final c in cols) c.label], w,
                  header: true, bg: Colors.grey.shade200),
              Flexible(
                child: rows.isEmpty
                    ? const SizedBox(
                        height: 60, child: Center(child: Text('No data in this period')))
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: rows.length,
                        itemBuilder: (_, i) => _row(rows[i], w,
                            bg: i.isOdd ? Colors.grey.shade50 : null,
                            onTap: onRowTap == null ? null : () => onRowTap!(i)),
                      ),
              ),
              if (footer != null)
                _row(footer!, w, bold: true, bg: Colors.grey.shade200),
            ]),
          ),
        ),
      );
    });
  }
}

class _Shell extends StatelessWidget {
  final String title;
  final _Period period;
  final void Function(_Period) onPeriod;
  final void Function(String) onSearch;
  final VoidCallback onRefresh;
  final VoidCallback? onExport;
  final AsyncValue<Map<String, dynamic>> data;
  final Widget Function(Map<String, dynamic>) body;

  const _Shell({
    required this.title,
    required this.period,
    required this.onPeriod,
    required this.onSearch,
    required this.onRefresh,
    required this.onExport,
    required this.data,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: Text(title),
          actions: [
            IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export',
                onPressed: onExport),
            IconButton(
                icon: const Icon(Icons.refresh_outlined),
                tooltip: 'Refresh',
                onPressed: onRefresh),
          ],
        ),
        _FilterBar(period: period, onChanged: onPeriod, onSearch: onSearch),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load report: ${api.sanitizeUiErrorMessage(e)}',
                  textAlign: TextAlign.center),
            )),
            data: body,
          ),
        ),
      ]),
    );
  }
}

Future<void> _export(BuildContext context,
    {required String name,
    required List<int> Function() xlsx,
    required Future<List<int>> Function() pdf}) async {
  final choice = await pickExport(context);
  if (choice == null || !context.mounted) return;
  final (format, action) = choice;
  final isPdf = format == ExportFormat.pdf;

  // Building a PDF runs on the UI thread and can take a couple of seconds;
  // without this the screen just sits there after "Share". Show a spinner,
  // wait for it to paint, then do the work.
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
        canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  await WidgetsBinding.instance.endOfFrame;
  List<int> bytes;
  try {
    bytes = isPdf ? await pdf() : xlsx();
  } catch (e) {
    nav.pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create file: ${api.sanitizeUiErrorMessage(e)}')));
    }
    return;
  }
  nav.pop();
  if (!context.mounted) return;
  await deliverExport(
    context,
    action,
    Uint8List.fromList(bytes),
    '$name-${DateFormat('dd-MMM-yyyy').format(DateTime.now())}.${isPdf ? 'pdf' : 'xlsx'}',
    isPdf ? StockReportExport.pdfMime : StockReportExport.xlsxMime,
  );
}

Widget _note(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black54)),
    );

// ---------------------------------------------------------------------------
// Opening & closing stock
// ---------------------------------------------------------------------------
class StockReportScreen extends ConsumerStatefulWidget {
  const StockReportScreen({super.key});
  @override
  ConsumerState<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends ConsumerState<StockReportScreen> {
  String _search = '';

  static const _cols = [
    _Col('Item', 120, left: true),
    _Col('Open', 52),
    _Col('Purchased', 60),
    _Col('Sold', 48),
    _Col('Close', 52),
  ];

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(stockPeriodProvider);
    final range = period.range;
    final data = ref.watch(_stockProvider);
    final d = data.valueOrNull;
    return _Shell(
      title: 'Opening & closing stock',
      period: period,
      onPeriod: (p) => ref.read(stockPeriodProvider.notifier).state = p,
      onSearch: (v) => setState(() => _search = v),
      onRefresh: () => ref.invalidate(_stockProvider),
      onExport: d == null
          ? null
          : () => _export(context,
              name: 'Stock',
              xlsx: () => StockReportExport.stockXlsx(_rows(d)),
              pdf: () => StockReportExport.stockPdf(_rows(d),
                  businessName: ref.read(businessNameProvider), period: _period(range))),
      data: data,
      body: (d) {
        final rows = _rows(d)
            .where((r) => '${r['name']}'.toLowerCase().contains(_search.toLowerCase()))
            .toList();
        double sum(String k) => rows.fold(0, (s, r) => s + _n(r[k]));
        final historyFrom = d['history_from'] as String?;
        return Column(children: [
          if (historyFrom != null && _iso(range.start).compareTo(historyFrom) <= 0)
            _note('Stock history starts on $historyFrom; earlier days show no data.'),
          _note('Tap an item to see it day by day.'),
          Expanded(
            child: _Grid(
              cols: _cols,
              rows: [
                for (final r in rows)
                  [
                    '${r['name']}',
                    _q(r['opening']),
                    _q(r['purchased']),
                    // Net of voided bills, so Close = Open + Purchased − Sold.
                    _q(_n(r['sold']) - _n(r['returned'])),
                    // Voided-bill returns and manual corrections, one column.
                    _q(r['closing']),
                  ],
              ],
              footer: [
                'Total (${rows.length})',
                _q(sum('opening')),
                _q(sum('purchased')),
                _q(sum('sold') - sum('returned')),
                _q(sum('closing')),
              ],
              onRowTap: (i) => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _StockDailyScreen(rows[i], range))),
            ),
          ),
        ]);
      },
    );
  }
}

// Day-by-day chain for one item: each day closes on what the next opens with.
class _StockDailyScreen extends ConsumerWidget {
  final Map<String, dynamic> r;
  final DateTimeRange range;
  const _StockDailyScreen(this.r, this.range);

  static const _cols = [
    _Col('Date', 90, left: true),
    _Col('Open', 52),
    _Col('Purchased', 60),
    _Col('Sold', 48),
    _Col('Close', 52),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_stockDailyProvider(
        (range, r['item_id'] as String?, r['variant_id'] as String?)));
    final days = async.valueOrNull == null
        ? null
        : ((async.valueOrNull!['days'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: Text('${r['name']}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export',
              onPressed: days == null
                  ? null
                  : () => _export(context,
                      name: 'Stock-${r['name']}'.replaceAll(RegExp(r'[^w-]+'), '_'),
                      xlsx: () => StockReportExport.dailyXlsx(days, item: '${r['name']}'),
                      pdf: () => StockReportExport.dailyPdf(days,
                          businessName: ref.read(businessNameProvider),
                          item: '${r['name']}',
                          period: _period(range))),
            ),
          ],
        ),
        _note('${_period(range)}  ·  each day closes on what the next day opens with'),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(api.sanitizeUiErrorMessage(e))),
            data: (d) {
              final days = ((d['days'] as List?) ?? const []).cast<Map>();
              return _Grid(cols: _cols, rows: [
                for (final x in days)
                  [
                    _shortDayFmt.format(DateTime.parse('${x['date']}')),
                    _q(x['opening']),
                    _q(x['purchased']),
                    _q(x['sold']),
                    _q(x['closing']),
                  ],
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Item-wise net profit
// ---------------------------------------------------------------------------
class ItemProfitScreen extends ConsumerStatefulWidget {
  const ItemProfitScreen({super.key});
  @override
  ConsumerState<ItemProfitScreen> createState() => _ItemProfitScreenState();
}

class _ItemProfitScreenState extends ConsumerState<ItemProfitScreen> {
  String _search = '';

  static const _cols = [
    _Col('Item', 110, left: true),
    _Col('Qty', 40),
    _Col('Buy', 50),
    _Col('Sell', 50),
    _Col('Margin', 50),
    _Col('Profit', 66),
    _Col('%', 38),
  ];

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(profitPeriodProvider);
    final range = period.range;
    final data = ref.watch(_profitProvider);
    final d = data.valueOrNull;
    return _Shell(
      title: 'Item-wise net profit',
      period: period,
      onPeriod: (p) => ref.read(profitPeriodProvider.notifier).state = p,
      onSearch: (v) => setState(() => _search = v),
      onRefresh: () => ref.invalidate(_profitProvider),
      onExport: d == null
          ? null
          : () => _export(context,
              name: 'Item-profit',
              xlsx: () => StockReportExport.profitXlsx(_rows(d)),
              pdf: () => StockReportExport.profitPdf(_rows(d),
                  businessName: ref.read(businessNameProvider),
                  period: _period(range),
                  totalProfit: _n((d['totals'] as Map)['profit']))),
      data: data,
      body: (d) {
        final t = Map<String, dynamic>.from(d['totals'] as Map);
        final rows = _rows(d)
            .where((r) => '${r['name']}'.toLowerCase().contains(_search.toLowerCase()))
            .toList();
        final noCost = _n(t['qty_no_cost']);
        return Column(children: [
          if (noCost > 0)
            _note(
                '${_q(noCost)} units have no buying price (never purchased, or sold before '
                'costs were tracked). They show "–" and are left out of cost and profit.',
                color: Colors.deepOrange),
          Expanded(
            child: _Grid(
              cols: _cols,
              rows: [
                for (final r in rows)
                  [
                    '${r['name']}',
                    _q(r['qty']),
                    _m(r['avg_cost']),
                    _m(r['avg_sell']),
                    (r['avg_sell'] == null || r['avg_cost'] == null)
                        ? '–'
                        : _m(_n(r['avg_sell']) - _n(r['avg_cost'])),
                    r['avg_cost'] == null ? '–' : _m(r['profit']),
                    r['margin_pct'] == null
                        ? '–'
                        : _n(r['margin_pct']).toStringAsFixed(1),
                  ],
              ],
              footer: [
                'Total (${rows.length})',
                _q(t['qty']),
                '',
                '',
                '',
                _m(t['profit']),
                '',
              ],
            ),
          ),
        ]);
      },
    );
  }
}
