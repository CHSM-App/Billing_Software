import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../storage.dart';
import '../theme/app_theme.dart';

// Sales returns — credit notes (backend: /api/bills/:id/returns,
// migration 082). A settled bill takes returns of some items or part of a
// quantity; each is a numbered credit note valued at the bill's own prices
// and discount. Stock comes back on the server.

final _rs = NumberFormat('#,##0.00');

/// A credit note as the server lists it.
typedef CreditNote = Map<String, dynamic>;

double _n(Object? v) => (v as num?)?.toDouble() ?? double.tryParse('$v') ?? 0;

/// Already returned per bill line: bill_item_id → qty.
Map<String, double> returnedByLine(List<CreditNote> notes) {
  final out = <String, double>{};
  for (final n in notes) {
    for (final i in (n['items'] as List? ?? [])) {
      final id = '${i['bill_item_id']}'.toLowerCase();
      out[id] = (out[id] ?? 0) + _n(i['quantity']);
    }
  }
  return out;
}

/// The bill's credit notes inside the bill detail dialog: number, date, how
/// it was refunded and what came back, with Print and (owner, same day) Undo.
class BillReturnsSection extends StatefulWidget {
  final Bill bill;
  final String userRole;
  final String businessName;
  final VoidCallback onChanged;
  const BillReturnsSection({
    super.key,
    required this.bill,
    required this.userRole,
    required this.businessName,
    required this.onChanged,
  });

  @override
  State<BillReturnsSection> createState() => _BillReturnsSectionState();
}

class _BillReturnsSectionState extends State<BillReturnsSection> {
  late Future<List<CreditNote>> _future = getReturns(widget.bill.id);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<List<CreditNote>>(
      future: _future,
      builder: (context, snap) {
        final notes = snap.data ?? const [];
        if (notes.isEmpty) return const SizedBox.shrink();
        final today = DateTime.now();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(height: AppSpacing.space24),
          Text(l10n.returnsTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final n in notes) ...[
            const SizedBox(height: AppSpacing.space8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.errorLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${n['return_number']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text('− ₹${_rs.format(_n(n['total']))}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
                ]),
                Text(
                    '${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse('${n['returned_at']}').toLocal())}'
                    ' · ${_refundLabel(context, '${n['refund_mode']}')}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                for (final i in (n['items'] as List? ?? []))
                  Text('${i['item_name']} × ${formatQty(_n(i['quantity']))}',
                      style: const TextStyle(fontSize: 12)),
                if ((n['reason'] ?? '').toString().isNotEmpty)
                  Text('${n['reason']}',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary)),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: () => printCreditNote(widget.bill, n, widget.businessName),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(l10n.returnPrint),
                  ),
                  // A mistake can be undone the same day, by the owner.
                  if (widget.userRole == 'owner' &&
                      DateUtils.isSameDay(DateTime.parse('${n['returned_at']}').toLocal(), today))
                    TextButton(
                      onPressed: () => _undo(n),
                      child: Text(l10n.returnUndo, style: const TextStyle(color: AppColors.error)),
                    ),
                ]),
              ]),
            ),
          ],
        ]);
      },
    );
  }

  Future<void> _undo(CreditNote n) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.returnUndo),
        content: Text(l10n.returnUndoConfirm('${n['return_number']}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.returnUndo, style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteReturn(widget.bill.id, '${n['id']}');
      if (!mounted) return;
      setState(() => _future = getReturns(widget.bill.id));
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error),
      );
    }
  }
}

String _refundLabel(BuildContext context, String mode) {
  final l10n = context.l10n;
  switch (mode) {
    case 'cash':
      return l10n.paymentCash;
    case 'upi':
      return l10n.paymentUpi;
    case 'card':
      return l10n.paymentCard;
    case 'credit':
      return l10n.returnRefundCredit;
    default:
      return l10n.paymentOther;
  }
}

/// Opens the "Return items" sheet for a settled bill. Returns the saved credit
/// note's number, or null when nothing was saved.
Future<String?> showReturnItemsSheet(BuildContext context, Bill bill) async {
  List<CreditNote> notes;
  try {
    notes = await getReturns(bill.id);
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReturnSheet(bill: bill, returned: returnedByLine(notes)),
  );
}

class _ReturnSheet extends StatefulWidget {
  final Bill bill;
  final Map<String, double> returned;
  const _ReturnSheet({required this.bill, required this.returned});

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final Map<String, double> _qty = {};
  final _reasonCtrl = TextEditingController();
  String _mode = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  double _left(BillItem i) =>
      (i.quantity - (widget.returned[i.id.toLowerCase()] ?? 0)).clamp(0, double.infinity).toDouble();

  /// A preview of the credit note: the bill's net rate, less its share of
  /// the bill discount, plus GST when the bill charged it. The server's
  /// figure is the one saved.
  double get _preview {
    final b = widget.bill;
    final ratio = b.subtotal > 0 ? (b.subtotal - b.discountAmount) / b.subtotal : 1.0;
    var total = 0.0;
    for (final i in b.items) {
      final q = _qty[i.id] ?? 0;
      if (q <= 0) continue;
      final net = q * i.unitPrice * ratio;
      total += net + (b.taxAmount > 0 && i.taxRate != null ? net * i.taxRate! / 100 : 0);
    }
    return total;
  }

  Future<void> _save() async {
    final lines = [
      for (final e in _qty.entries)
        if (e.value > 0) {'bill_item_id': e.key, 'quantity': e.value},
    ];
    if (lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      final note = await createReturn(widget.bill.id, {
        'lines': lines,
        'refund_mode': _mode,
        if (_reasonCtrl.text.trim().isNotEmpty) 'reason': _reasonCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, '${note['return_number']}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final b = widget.bill;
    final modes = [
      ('cash', l10n.paymentCash),
      ('upi', l10n.paymentUpi),
      ('card', l10n.paymentCard),
      ('other', l10n.paymentOther),
      // Taken off what a credit bill still owes.
      if (b.isUnpaidCredit) ('credit', l10n.returnRefundCredit),
    ];
    final any = _qty.values.any((q) => q > 0);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(l10n.returnItemsTitle(b.billNumber),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.returnItemsHint,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          for (final i in b.items)
            if (_left(i) > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.itemName, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(l10n.returnQtyLeft(formatQty(_left(i))),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                  IconButton(
                    onPressed: (_qty[i.id] ?? 0) <= 0
                        ? null
                        : () => setState(() => _qty[i.id] = ((_qty[i.id] ?? 0) - 1).clamp(0, _left(i)).toDouble()),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(formatQty(_qty[i.id] ?? 0), textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: (_qty[i.id] ?? 0) >= _left(i)
                        ? null
                        // A part unit (0.5 kg left) is returned whole in one tap.
                        : () => setState(() => _qty[i.id] = ((_qty[i.id] ?? 0) + 1).clamp(0, _left(i)).toDouble()),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ]),
              ),
          const SizedBox(height: 8),
          Text(l10n.returnRefundBy, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (value, label) in modes)
              ChoiceChip(
                label: Text(label),
                selected: _mode == value,
                onSelected: (_) => setState(() => _mode = value),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            maxLength: 200,
            decoration: InputDecoration(
                labelText: l10n.returnReason, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: !any || _saving ? null : _save,
            child: Text(any
                ? l10n.returnSave('₹${_rs.format(_preview)}')
                : l10n.returnChooseItems),
          ),
        ]),
      ),
    );
  }
}

/// Prints / shares a credit note as a PDF (A5): the business, the note and
/// the invoice it corrects, the lines and the GST split (CGST/SGST halves,
/// as on the bill).
Future<void> printCreditNote(Bill bill, CreditNote n, String businessName) async {
  final profile = await getGstProfile();
  final gstin = (profile['gst_number'] ?? '').toString();
  final tax = _n(n['tax_amount']);
  final paise = (tax * 100).round();
  final cgst = ((paise + 1) >> 1) / 100;
  final sgst = (paise >> 1) / 100;
  String m(double v) => 'Rs. ${_rs.format(v)}';
  final date = DateFormat('dd MMM yyyy').format(DateTime.parse('${n['returned_at']}').toLocal());
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(businessName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      if (gstin.isNotEmpty && tax > 0) pw.Text('GSTIN: $gstin'),
      pw.SizedBox(height: 10),
      pw.Text('CREDIT NOTE', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.Text('No: ${n['return_number']}    Date: $date'),
      pw.Text('Against invoice: ${bill.billNumber}'
          '  (${DateFormat('dd MMM yyyy').format(bill.billDate.toLocal())})'),
      if ((bill.customerName ?? '').isNotEmpty) pw.Text('Customer: ${bill.customerName}'),
      if ((bill.customerGstin ?? '').isNotEmpty) pw.Text('Customer GSTIN: ${bill.customerGstin}'),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: ['Item', 'Qty', 'Taxable', 'GST %', 'GST'],
        data: [
          for (final i in (n['items'] as List? ?? []))
            [
              '${i['item_name']}',
              formatQty(_n(i['quantity'])),
              _rs.format(_n(i['net_amount'])),
              i['tax_rate'] == null ? '-' : '${_n(i['tax_rate'])}',
              _rs.format(_n(i['tax_amount'])),
            ],
        ],
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
      pw.Text('Taxable value: ${m(_n(n['subtotal']))}'),
      if (tax > 0) pw.Text('CGST: ${m(cgst)}    SGST: ${m(sgst)}'),
      pw.Text('Total credit: ${m(_n(n['total']))}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text('Refunded by: ${n['refund_mode']}'),
      if ((n['reason'] ?? '').toString().isNotEmpty) pw.Text('Reason: ${n['reason']}'),
    ]),
  ));
  await Printing.layoutPdf(
      name: '${n['return_number']}.pdf', onLayout: (_) async => doc.save());
}
