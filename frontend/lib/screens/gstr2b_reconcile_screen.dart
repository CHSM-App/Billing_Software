import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api.dart' as api;
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/gst_period_selector.dart';
import '../widgets/shell_app_bar.dart';

final _money = NumberFormat('#,##0.00');

double _n(Object? v) => v == null ? 0 : double.tryParse(v.toString()) ?? 0;
String _m(Object? v) => _money.format(_n(v));

/// Extract the B2B invoices from a GSTR-2B file downloaded from the GST portal.
///
/// Parsing happens ON DEVICE so only the essentials are sent to the server: a
/// real 2B file can be several MB, well past the API's 100KB body limit.
///
/// The portal has shipped the payload under several shapes over time, so the
/// known locations are tried in order. Throws [FormatException] with a readable
/// message when none match — reporting "everything is missing" would be far
/// more misleading than saying the file was not understood.
List<Map<String, dynamic>> extractGstr2bInvoices(Map<String, dynamic> raw) {
  List? b2b;
  final data = raw['data'];
  if (data is Map) {
    final docdata = data['docdata'];
    final docsumm = data['docsumm'];
    if (docdata is Map && docdata['b2b'] is List) b2b = docdata['b2b'] as List;
    b2b ??= data['b2b'] is List ? data['b2b'] as List : null;
    if (b2b == null && docsumm is Map && docsumm['b2b'] is List) {
      b2b = docsumm['b2b'] as List;
    }
  }
  if (b2b == null) {
    final docdata = raw['docdata'];
    if (docdata is Map && docdata['b2b'] is List) b2b = docdata['b2b'] as List;
  }
  b2b ??= raw['b2b'] is List ? raw['b2b'] as List : null;

  if (b2b == null || b2b.isEmpty) {
    throw const FormatException(
        'This does not look like a GSTR-2B file. Download the JSON from the '
        'GST portal (Returns Dashboard → GSTR-2B → Download JSON) and paste it here.');
  }

  final out = <Map<String, dynamic>>[];
  for (final s in b2b) {
    if (s is! Map) continue;
    for (final inv in (s['inv'] as List? ?? [])) {
      if (inv is! Map) continue;
      double taxable = 0, cgst = 0, sgst = 0, igst = 0, cess = 0;
      for (final it in (inv['itms'] as List? ?? [])) {
        if (it is! Map) continue;
        final d = it['itm_det'];
        if (d is! Map) continue;
        taxable += _n(d['txval']);
        cgst += _n(d['camt']);
        sgst += _n(d['samt']);
        igst += _n(d['iamt']);
        cess += _n(d['csamt']);
      }
      out.add({
        'gstin': (s['ctin'] ?? '').toString().trim().toUpperCase(),
        'vendor_name': (s['trdnm'] ?? '').toString(),
        'invoice_number': (inv['inum'] ?? '').toString().trim(),
        // Left as the portal wrote it (DD-MM-YYYY); the server normalises.
        'invoice_date': (inv['idt'] ?? '').toString().trim(),
        'invoice_value': _n(inv['val']),
        'taxable_value': taxable,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'cess': cess,
      });
    }
  }
  return out;
}

/// Imports a GSTR-2B statement and reconciles it against recorded purchases.
class Gstr2bReconcileScreen extends ConsumerStatefulWidget {
  final GstPeriod period;

  const Gstr2bReconcileScreen({super.key, required this.period});

  @override
  ConsumerState<Gstr2bReconcileScreen> createState() =>
      _Gstr2bReconcileScreenState();
}

class _Gstr2bReconcileScreenState
    extends ConsumerState<Gstr2bReconcileScreen> {
  final _jsonCtrl = TextEditingController();
  late GstPeriod _period;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _period = widget.period;
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const ShellAppBar(title: Text('GSTR-2B reconciliation')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GstCard(
                title: 'Period',
                child: GstPeriodSelector(
                  period: _period,
                  onChanged: (p) => setState(() {
                    _period = p;
                    _result = null;
                  }),
                ),
              ),
              const SizedBox(height: 16),
              _importCard(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                GstCard(
                  title: 'Could not read the file',
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.error)),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                ..._results(_result!),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _importCard() {
    return GstCard(
      title: 'Import GSTR-2B',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'On the GST portal: Returns Dashboard → select the period → GSTR-2B '
          '→ Download JSON. Open the downloaded file and paste its contents below.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jsonCtrl,
          maxLines: 5,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: '{"data": {"docdata": {"b2b": [ ... ]}}}',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            text: _busy ? 'Reconciling…' : 'Reconcile',
            onPressed: _busy ? null : _reconcile,
          ),
        ),
      ]),
    );
  }

  Future<void> _reconcile() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final text = _jsonCtrl.text.trim();
      if (text.isEmpty) {
        setState(() => _error = 'Paste the GSTR-2B JSON first.');
        return;
      }
      // Parse locally so a malformed file fails fast, before any network call.
      late final List<Map<String, dynamic>> invoices;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('The pasted text is not a GSTR-2B file.');
        }
        invoices = extractGstr2bInvoices(decoded);
      } on FormatException catch (e) {
        setState(() => _error = e.message);
        return;
      }

      final res = await api.reconcileGstr2b(
        from: _period.fromApi,
        to: _period.toApi,
        invoices: invoices,
      );
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) setState(() => _error = api.sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _results(Map<String, dynamic> r) {
    final s = Map<String, dynamic>.from(r['summary'] ?? {});
    final diff = _n(s['itc_difference']);

    return [
      GstCard(
        title: 'Input tax credit',
        child: Column(children: [
          GstKv('Available per GSTR-2B', _m(s['itc_available_2b'])),
          GstKv('Claimed in your books', _m(s['itc_claimed_books'])),
          const Divider(height: 20),
          GstKv(
            'Difference',
            _m(s['itc_difference']),
            bold: true,
            // Negative means more credit is claimed in books than the portal
            // will allow — the number that costs real money.
            valueColor: diff < 0 ? AppColors.error : AppColors.success,
          ),
          if (diff < 0) ...[
            const SizedBox(height: 8),
            const Text(
              'You have claimed more credit than GSTR-2B supports. Check the '
              '"Not in GSTR-2B" list below — those suppliers may not have filed.',
              style: TextStyle(fontSize: 11, color: AppColors.error),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      _bucket('Matched', s['matched_count'], s['matched_tax'],
          r['matched'] as List? ?? [], AppColors.success, matched: true),
      const SizedBox(height: 12),
      _bucket('Matched with differences', s['mismatch_count'],
          s['mismatch_tax'], r['mismatched'] as List? ?? [], AppColors.warning,
          matched: true, showDiff: true),
      const SizedBox(height: 12),
      _bucket('In GSTR-2B, not in your books', s['missing_in_books_count'],
          s['missing_in_books_tax'], r['missing_in_books'] as List? ?? [],
          AppColors.error),
      const SizedBox(height: 12),
      _bucket('In your books, not in GSTR-2B', s['missing_in_2b_count'],
          s['missing_in_2b_tax'], r['missing_in_2b'] as List? ?? [],
          AppColors.error),
    ];
  }

  Widget _bucket(String title, Object? count, Object? tax, List rows,
      Color colour,
      {bool matched = false, bool showDiff = false}) {
    final n = int.tryParse('${count ?? 0}') ?? 0;
    return GstCard(
      title: '$title ($n)',
      trailing: Text('Rs. ${_m(tax)}',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: colour)),
      child: rows.isEmpty
          ? const Text('Nothing here.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          : Column(
              children: [
                for (final e in rows.take(50))
                  _row(Map<String, dynamic>.from(e as Map),
                      matched: matched, showDiff: showDiff),
                if (rows.length > 50)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('…and ${rows.length - 50} more',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ),
              ],
            ),
    );
  }

  Widget _row(Map<String, dynamic> e,
      {bool matched = false, bool showDiff = false}) {
    final diffs = (e['differences'] as List? ?? []).cast<String>();
    final tax = matched
        ? _n((e['books'] as Map?)?['total_tax'])
        : _n(e['total_tax']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${e['vendor_name'] ?? ''} · ${e['invoice_number'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
          Text('Rs. ${_money.format(tax)}',
              style: const TextStyle(fontSize: 12)),
        ]),
        Text(
          '${e['gstin'] ?? ''} · ${e['invoice_date'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        if (e['period_mismatch'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Dated outside this period',
                style: TextStyle(fontSize: 11, color: AppColors.warning)),
          ),
        if (showDiff && diffs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              children: [
                for (final d in diffs)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_diffLabel(d),
                        style: const TextStyle(fontSize: 10)),
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  String _diffLabel(String d) {
    switch (d) {
      case 'invoice_date':
        return 'date differs';
      case 'taxable_value':
        return 'taxable value differs';
      case 'tax_amount':
        return 'tax differs';
      default:
        return d;
    }
  }
}
