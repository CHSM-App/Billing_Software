import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api.dart' as api;
import '../theme/app_theme.dart';
import '../widgets/gst_period_selector.dart';
import '../widgets/shell_app_bar.dart';
import 'gstr2b_reconcile_screen.dart';

final _money = NumberFormat('#,##0.00');

double _n(Object? v) => v == null ? 0 : double.tryParse(v.toString()) ?? 0;
String _m(Object? v) => _money.format(_n(v));

final gstr2PeriodProvider =
    StateProvider<GstPeriod>((ref) => GstPeriod.current());

final gstr2ReportProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final p = ref.watch(gstr2PeriodProvider);
  return api.getGstr2Report(from: p.fromApi, to: p.toApi);
});

/// GSTR-2 — the input tax credit summary of recorded purchases.
///
/// NOT a filed return: GSTR-2 was suspended in 2017. This is the inward-supply
/// summary used to reconcile against GSTR-2B and to fill GSTR-3B Table 4, and
/// the screen says so rather than implying it can be filed.
class Gstr2Screen extends ConsumerWidget {
  const Gstr2Screen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(gstr2PeriodProvider);
    final report = ref.watch(gstr2ReportProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: const Text('GSTR-2 (Purchases)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(gstr2ReportProvider),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(gstr2ReportProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GstCard(
                  title: 'Filing period',
                  child: GstPeriodSelector(
                    period: period,
                    onChanged: (p) =>
                        ref.read(gstr2PeriodProvider.notifier).state = p,
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
                                ref.invalidate(gstr2ReportProvider),
                            child: const Text('Retry'),
                          ),
                        ]),
                  ),
                  data: (r) => _body(context, ref, r, period),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Map<String, dynamic> r,
      GstPeriod period) {
    final t = Map<String, dynamic>.from(r['totals'] ?? {});
    final byRate = (r['by_rate'] as List? ?? []);
    final b2b = (r['b2b'] as List? ?? []);
    final hsn = (r['hsn'] as List? ?? []);
    final unreg = Map<String, dynamic>.from(r['unregistered'] ?? {});

    return Column(children: [
      GstCard(
        title: 'Input tax credit',
        child: Column(children: [
          GstKv('Purchases', '${t['bill_count'] ?? 0}'),
          GstKv('Invoice value', _m(t['invoice_value'])),
          const Divider(height: 20),
          GstKv('Taxable value', _m(t['taxable_value'])),
          GstKv('CGST', _m(t['cgst'])),
          GstKv('SGST', _m(t['sgst'])),
          GstKv('IGST', _m(t['igst'])),
          const Divider(height: 20),
          GstKv('ITC claimable', _m(t['itc_eligible_tax']),
              bold: true, valueColor: AppColors.success),
          if (_n(t['itc_ineligible_tax']) > 0)
            GstKv('Not claimable', _m(t['itc_ineligible_tax']),
                valueColor: AppColors.error),
          if (_n(t['reverse_charge_tax']) > 0)
            GstKv('Reverse charge', _m(t['reverse_charge_tax'])),
        ]),
      ),
      const SizedBox(height: 16),
      GstCard(
        title: 'Rate-wise',
        child: GstTable(
          headers: const ['Rate %', 'Taxable', 'CGST', 'SGST', 'IGST', 'ITC'],
          rows: [
            for (final e in byRate)
              [
                _n((e as Map)['rate']).toStringAsFixed(2),
                _m(e['taxable_value']),
                _m(e['cgst']),
                _m(e['sgst']),
                _m(e['igst']),
                _m(e['itc_eligible_tax']),
              ]
          ],
        ),
      ),
      const SizedBox(height: 16),
      GstCard(
        title: 'By supplier (B2B)',
        child: GstTable(
          headers: const ['GSTIN', 'Vendor', 'Taxable', 'Tax', 'ITC'],
          rows: [
            for (final e in b2b)
              [
                ((e as Map)['gstin'] ?? '').toString(),
                (e['vendor_name'] ?? '').toString(),
                _m(e['taxable_value']),
                _m(e['total_tax']),
                e['itc_eligible'] == true ? 'Yes' : 'No',
              ]
          ],
        ),
      ),
      if (_n(unreg['taxable_value']) > 0) ...[
        const SizedBox(height: 16),
        GstCard(
          title: 'Unregistered vendors',
          child: Column(children: [
            GstKv('Taxable value', _m(unreg['taxable_value'])),
            GstKv('Tax paid', _m(unreg['total_tax'])),
            const SizedBox(height: 8),
            const Text(
              'An unregistered vendor cannot pass on credit, so no ITC is '
              'claimable on these purchases.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      GstCard(
        title: 'HSN summary',
        child: GstTable(
          headers: const ['HSN/SAC', 'Qty', 'Rate %', 'Taxable', 'Tax'],
          rows: [
            for (final e in hsn)
              [
                ((e as Map)['hsn'] ?? '—').toString(),
                _n(e['quantity']).toStringAsFixed(2),
                _n(e['rate']).toStringAsFixed(2),
                _m(e['taxable_value']),
                _m(e['total_tax']),
              ]
          ],
        ),
      ),
      const SizedBox(height: 16),
      GstCard(
        title: 'Reconcile with GSTR-2B',
        child: Column(children: [
          const Text(
            'GSTR-2B is generated by the GST portal from your suppliers\' own '
            'filings. Import it to see which purchases your suppliers actually '
            'reported — ITC cannot be claimed on the ones they did not.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Open reconciliation'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Gstr2bReconcileScreen(period: period)),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'GSTR-2 is not a filed return — it was suspended in 2017. These '
          'figures are your purchase ITC summary, used to reconcile against '
          'GSTR-2B and to fill GSTR-3B Table 4.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    ]);
  }
}
