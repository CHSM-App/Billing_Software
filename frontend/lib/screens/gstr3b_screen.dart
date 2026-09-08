import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart' as api;
import '../services/gstr3b_export.dart';
import '../theme/app_theme.dart';
import '../widgets/gst_period_selector.dart';
import '../widgets/shell_app_bar.dart';

final _money = NumberFormat('#,##0.00');

double _n(Object? v) => v == null ? 0 : double.tryParse(v.toString()) ?? 0;
String _m(Object? v) => _money.format(_n(v));

final gstr3bPeriodProvider =
    StateProvider<GstPeriod>((ref) => GstPeriod.current());

final gstr3bReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final p = ref.watch(gstr3bPeriodProvider);
  return api.getGstr3bReport(from: p.fromApi, to: p.toApi);
});

/// GSTR-3B — the monthly summary return that IS still filed.
///
/// Shows the three tables a small retailer or restaurant actually fills:
/// 3.1 (outward supplies), 4 (eligible ITC) and 6.1 (tax payable after credit).
/// Cells the app holds no data for are listed as "not tracked" rather than
/// shown as zero, so nothing here reads as a verified nil that was never checked.
class Gstr3bScreen extends ConsumerWidget {
  const Gstr3bScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(gstr3bPeriodProvider);
    final report = ref.watch(gstr3bReportProvider);
    // Null while loading or after an error — the download control stays
    // disabled until there is a real report to write out.
    final data = report.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: const Text('GSTR-3B'),
          actions: [
            GstDownloadAction(
              enabled: data != null,
              onCsv: () => _downloadCsv(context, data!, period),
              onPdf: () => _downloadPdf(context, data!, period),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(gstr3bReportProvider),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(gstr3bReportProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GstCard(
                  title: 'Filing period',
                  child: GstPeriodSelector(
                    period: period,
                    onChanged: (p) =>
                        ref.read(gstr3bPeriodProvider.notifier).state = p,
                  ),
                ),
                const SizedBox(height: 16),
                report.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => GstCard(
                    title: 'Could not load',
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(api.sanitizeUiErrorMessage(e),
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () =>
                                ref.invalidate(gstr3bReportProvider),
                            child: const Text('Retry'),
                          ),
                        ]),
                  ),
                  data: _body,
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // -------------------------------------------------------------------------
  // Downloads
  //
  // No busy flag, unlike GSTR-1: both actions immediately hand off to a modal
  // platform sheet (share / print), which blocks a second tap on its own. The
  // report map is passed in rather than re-read, so the file always matches
  // the period that was on screen when the menu was opened.
  // -------------------------------------------------------------------------

  Future<void> _downloadCsv(
      BuildContext context, Map<String, dynamic> r, GstPeriod period) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = Gstr3bExport.buildCsv(r);
      await Share.shareXFiles(
        [
          XFile.fromData(bytes,
              name: 'GSTR3B-${period.slug}.csv', mimeType: 'text/csv')
        ],
        text: 'GSTR-3B ${period.label}',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not create CSV: '
              '${api.sanitizeUiErrorMessage(e)}')));
    }
  }

  Future<void> _downloadPdf(
      BuildContext context, Map<String, dynamic> r, GstPeriod period) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await Gstr3bExport.buildPdf(r);
      // layoutPdf gives the platform's own print/save-as-PDF sheet, matching
      // how GSTR-1 and invoices are already emitted.
      await Printing.layoutPdf(
          onLayout: (_) async => bytes, name: 'GSTR3B-${period.slug}');
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not create PDF: '
              '${api.sanitizeUiErrorMessage(e)}')));
    }
  }

  Widget _body(Map<String, dynamic> r) {
    final t31 = Map<String, dynamic>.from(r['table_3_1'] ?? {});
    final t4 = Map<String, dynamic>.from(r['table_4'] ?? {});
    final t61 = Map<String, dynamic>.from(r['table_6_1'] ?? {});
    final liab = Map<String, dynamic>.from(t61['liability'] ?? {});
    final viaItc = Map<String, dynamic>.from(t61['paid_through_itc'] ?? {});
    final cash = Map<String, dynamic>.from(t61['payable_in_cash'] ?? {});

    return Column(children: [
      // The headline: what actually has to be paid this month.
      GstCard(
        title: 'Payable in cash',
        child: Column(children: [
          Text('Rs. ${_m(cash['total'])}',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            'Tax due Rs. ${_m(liab['total'])} less credit used '
            'Rs. ${_m(viaItc['total'])}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
      const SizedBox(height: 16),
      GstCard(
        title: '3.1(a) — Outward taxable supplies',
        child: Column(children: [
          GstKv('Taxable value', _m(t31['taxable_value'])),
          GstKv('CGST', _m(t31['cgst'])),
          GstKv('SGST', _m(t31['sgst'])),
          GstKv('IGST', _m(t31['igst'])),
        ]),
      ),
      const SizedBox(height: 16),
      GstCard(
        title: '4(A)(5) — Eligible ITC',
        child: Column(children: [
          GstKv('CGST', _m(t4['cgst'])),
          GstKv('SGST', _m(t4['sgst'])),
          GstKv('IGST', _m(t4['igst'])),
          const Divider(height: 20),
          GstKv('Total credit', _m(t4['total']), bold: true),
          const SizedBox(height: 6),
          const Text(
            'From purchases with a registered vendor GSTIN, excluding blocked '
            'credit and reverse-charge bills.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      GstCard(
        title: '6.1 — Payment of tax',
        child: GstTable(
          headers: const ['', 'CGST', 'SGST', 'IGST', 'Total'],
          rows: [
            [
              'Tax payable',
              _m(liab['cgst']),
              _m(liab['sgst']),
              _m(liab['igst']),
              _m(liab['total'])
            ],
            [
              'Paid via ITC',
              _m(viaItc['cgst']),
              _m(viaItc['sgst']),
              _m(viaItc['igst']),
              _m(viaItc['total'])
            ],
            [
              'Payable in cash',
              _m(cash['cgst']),
              _m(cash['sgst']),
              _m(cash['igst']),
              _m(cash['total'])
            ],
          ],
        ),
      ),
      if (_n(t61['itc_balance_carried']) > 0) ...[
        const SizedBox(height: 16),
        GstCard(
          title: 'Credit carried forward',
          child: Column(children: [
            GstKv('Unused ITC', _m(t61['itc_balance_carried']), bold: true),
            const SizedBox(height: 6),
            const Text(
              'Credit left over after settling this period\'s liability. It '
              'stays in your electronic credit ledger.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      const GstCard(
        title: 'Not included',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'This app does not record zero-rated, exempt or nil-rated supplies, '
            'imports, ISD credit, or ITC reversals, so tables 3.1(b)–(e), 3.2, '
            '4(B) and 5 are left blank rather than filled with zeroes. Enter '
            'those directly on the portal if they apply to you.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ]),
      ),
    ]);
  }
}
