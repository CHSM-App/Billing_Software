import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart' as api;
import '../services/gstr1_export.dart';
import '../theme/app_theme.dart';
import '../widgets/shell_app_bar.dart';

final _money = NumberFormat('#,##0.00');
final _apiDate = DateFormat('yyyy-MM-dd');

/// Whether the filing period is a calendar month or a quarter.
enum Gstr1PeriodType { monthly, quarterly }

/// A GSTR-1 filing period — the month or quarter the return covers.
class Gstr1Period {
  final Gstr1PeriodType type;
  final int year;

  /// 1-12 for monthly; 1-4 for quarterly.
  final int index;

  const Gstr1Period(
      {required this.type, required this.year, required this.index});

  /// Inclusive first day of the period.
  DateTime get from => type == Gstr1PeriodType.monthly
      ? DateTime(year, index, 1)
      : DateTime(year, (index - 1) * 3 + 1, 1);

  /// Inclusive last day. Day 0 of the following month is that month's last day,
  /// which handles February and leap years without a special case.
  DateTime get to => type == Gstr1PeriodType.monthly
      ? DateTime(year, index + 1, 0)
      : DateTime(year, (index - 1) * 3 + 4, 0);

  String get label => type == Gstr1PeriodType.monthly
      ? DateFormat('MMMM yyyy').format(from)
      : 'Q$index ${DateFormat('yyyy').format(from)} '
          '(${DateFormat('MMM').format(from)}–${DateFormat('MMM').format(to)})';

  /// Short form for filenames, e.g. 2026-08 or 2026-Q3.
  String get slug => type == Gstr1PeriodType.monthly
      ? DateFormat('yyyy-MM').format(from)
      : '$year-Q$index';
}

/// The period currently being viewed. Defaults to the current calendar month.
final gstr1PeriodProvider = StateProvider<Gstr1Period>((ref) {
  final now = DateTime.now();
  return Gstr1Period(
      type: Gstr1PeriodType.monthly, year: now.year, index: now.month);
});

/// The report for the selected period.
final gstr1ReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final p = ref.watch(gstr1PeriodProvider);
  return api.getGstr1Report(
    from: _apiDate.format(p.from),
    to: _apiDate.format(p.to),
  );
});

/// GSTR-1 outward-supplies report with monthly/quarterly selection and
/// CSV + PDF download.
///
/// All supplies are reported as B2C: bills carry no buyer GSTIN, so the return
/// is a consolidated rate-wise (B2CS) section plus an HSN summary rather than
/// an invoice-wise B2B listing.
class Gstr1Screen extends ConsumerStatefulWidget {
  const Gstr1Screen({super.key});

  @override
  ConsumerState<Gstr1Screen> createState() => _Gstr1ScreenState();
}

class _Gstr1ScreenState extends ConsumerState<Gstr1Screen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(gstr1PeriodProvider);
    final report = ref.watch(gstr1ReportProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: const Text('GSTR-1'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(gstr1ReportProvider),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(gstr1ReportProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _periodSelector(period),
                const SizedBox(height: 16),
                report.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => _errorBox(e),
                  data: _reportBody,
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // -------------------------------------------------------------------------
  // Period selection
  // -------------------------------------------------------------------------

  Widget _periodSelector(Gstr1Period p) {
    return _Card(
      title: 'Filing period',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<Gstr1PeriodType>(
            segments: const [
              ButtonSegment(
                  value: Gstr1PeriodType.monthly, label: Text('Monthly')),
              ButtonSegment(
                  value: Gstr1PeriodType.quarterly, label: Text('Quarterly')),
            ],
            selected: {p.type},
            onSelectionChanged: (s) {
              final type = s.first;
              final now = DateTime.now();
              // Switching type re-anchors to the current month/quarter so the
              // index is always valid for the new type (a month index of 11
              // is meaningless as a quarter).
              ref.read(gstr1PeriodProvider.notifier).state = Gstr1Period(
                type: type,
                year: now.year,
                index: type == Gstr1PeriodType.monthly
                    ? now.month
                    : ((now.month - 1) ~/ 3) + 1,
              );
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous period',
              onPressed: () => _shift(-1),
            ),
            Expanded(
              child: Text(
                p.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next period',
              // Never let the user page into a period that hasn't happened.
              onPressed: _canGoForward(p) ? () => _shift(1) : null,
            ),
          ]),
          Center(
            child: Text(
              '${DateFormat('dd MMM yyyy').format(p.from)} — '
              '${DateFormat('dd MMM yyyy').format(p.to)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  bool _canGoForward(Gstr1Period p) {
    final now = DateTime.now();
    final currentStart = p.type == Gstr1PeriodType.monthly
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
    return p.from.isBefore(currentStart);
  }

  void _shift(int delta) {
    final p = ref.read(gstr1PeriodProvider);
    var year = p.year;
    var index = p.index + delta;
    final max = p.type == Gstr1PeriodType.monthly ? 12 : 4;
    while (index < 1) {
      index += max;
      year--;
    }
    while (index > max) {
      index -= max;
      year++;
    }
    ref.read(gstr1PeriodProvider.notifier).state =
        Gstr1Period(type: p.type, year: year, index: index);
  }

  // -------------------------------------------------------------------------
  // Report body
  // -------------------------------------------------------------------------

  Widget _reportBody(Map<String, dynamic> r) {
    final totals = Map<String, dynamic>.from(r['totals'] ?? {});
    final b2cs = (r['b2cs'] as List? ?? []);
    final hsn = (r['hsn'] as List? ?? []);
    final hasData = b2cs.isNotEmpty || hsn.isNotEmpty;

    return Column(children: [
      _Card(
        title: 'Summary',
        child: Column(children: [
          _kv('Invoices', '${totals['bill_count'] ?? 0}'),
          _kv('Invoice value', _money.format(_n(totals['invoice_value']))),
          const Divider(height: 20),
          _kv('Taxable value', _money.format(_n(totals['taxable_value']))),
          _kv('CGST', _money.format(_n(totals['cgst']))),
          _kv('SGST', _money.format(_n(totals['sgst']))),
          const Divider(height: 20),
          _kv('Total tax', _money.format(_n(totals['total_tax'])), bold: true),
        ]),
      ),
      const SizedBox(height: 16),
      _Card(
        title: 'B2CS — rate-wise',
        child: b2cs.isEmpty
            ? _empty()
            : _table(
                headers: const ['Rate %', 'Taxable', 'CGST', 'SGST'],
                rows: [
                  for (final e in b2cs)
                    [
                      _n((e as Map)['rate']).toStringAsFixed(2),
                      _money.format(_n(e['taxable_value'])),
                      _money.format(_n(e['cgst'])),
                      _money.format(_n(e['sgst'])),
                    ]
                ],
              ),
      ),
      const SizedBox(height: 16),
      _Card(
        title: 'HSN summary',
        child: hsn.isEmpty
            ? _empty()
            : _table(
                headers: const ['HSN/SAC', 'Qty', 'Rate %', 'Taxable', 'Tax'],
                rows: [
                  for (final e in hsn)
                    [
                      ((e as Map)['hsn'] ?? '—').toString(),
                      _n(e['quantity']).toStringAsFixed(2),
                      _n(e['rate']).toStringAsFixed(2),
                      _money.format(_n(e['taxable_value'])),
                      _money.format(_n(e['total_tax'])),
                    ]
                ],
              ),
      ),
      const SizedBox(height: 16),
      _Card(
        title: 'Download',
        child: Column(children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('CSV'),
                onPressed: _busy || !hasData ? null : () => _downloadCsv(r),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
                onPressed: _busy || !hasData ? null : () => _downloadPdf(r),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'All supplies are reported as B2C (consolidated by rate). '
            'Intra-state supply assumed — tax splits as CGST + SGST.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ]),
      ),
    ]);
  }

  // -------------------------------------------------------------------------
  // Downloads
  // -------------------------------------------------------------------------

  Future<void> _downloadCsv(Map<String, dynamic> r) async {
    setState(() => _busy = true);
    try {
      final bytes = Gstr1Export.buildCsv(r);
      final name = 'GSTR1-${ref.read(gstr1PeriodProvider).slug}.csv';
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: name, mimeType: 'text/csv')],
        text: 'GSTR-1 ${ref.read(gstr1PeriodProvider).label}',
      );
    } catch (e) {
      _toast('Could not create CSV: ${api.sanitizeUiErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadPdf(Map<String, dynamic> r) async {
    setState(() => _busy = true);
    try {
      final bytes = await Gstr1Export.buildPdf(r);
      final name = 'GSTR1-${ref.read(gstr1PeriodProvider).slug}';
      // layoutPdf gives the platform's own print/save-as-PDF sheet, matching
      // how invoices are already emitted elsewhere in the app.
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    } catch (e) {
      _toast('Could not create PDF: ${api.sanitizeUiErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------------------------------------------------------------
  // Small pieces
  // -------------------------------------------------------------------------

  static double _n(Object? v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  Widget _empty() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No taxable sales in this period.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );

  Widget _errorBox(Object e) => _Card(
        title: 'Could not load',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(api.sanitizeUiErrorMessage(e),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(gstr1ReportProvider),
            child: const Text('Retry'),
          ),
        ]),
      );

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Text(v,
                style: TextStyle(
                    fontSize: bold ? 15 : 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
        ),
      );

  /// Horizontally scrollable so a wide table never overflows a phone screen.
  Widget _table(
      {required List<String> headers, required List<List<String>> rows}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 44,
        columnSpacing: 22,
        columns: [
          for (final h in headers)
            DataColumn(
                label: Text(h,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)))
        ],
        rows: [
          for (final r in rows)
            DataRow(
                cells: [
                  for (final c in r)
                    DataCell(Text(c, style: const TextStyle(fontSize: 12)))
                ])
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
