import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart' show Printing;

import '../api.dart' as api;
import '../l10n/l10n_ext.dart';
import '../models/models.dart' show formatQty, unitShort;
import '../providers.dart';
import '../services/purchase_list_pdf_import.dart';
import '../theme/app_theme.dart';
import '../utils/jpeg_compress.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/stock_target_picker.dart';
import 'purchase_list_screen.dart';
import 'stock_batches_screen.dart';

final _money = NumberFormat('#,##0.00');
final _dateFmt = DateFormat('dd MMM yyyy');

/// A derived per-unit rate rarely lands on two decimals — an amount split
/// across an awkward quantity gives 166.6667. Showing the extra digits when
/// they exist keeps the number honest about what the server was sent, while a
/// clean rate still reads as a plain 50.00.
String _rate(double v) {
  final two = v.toStringAsFixed(2);
  return double.parse(two) == v ? _money.format(v) : v.toStringAsFixed(4);
}

final _apiDate = DateFormat('yyyy-MM-dd');

/// The month currently being listed.
final vendorBillMonthProvider = StateProvider<DateTime>((ref) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, 1);
});

final vendorBillsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final m = ref.watch(vendorBillMonthProvider);
  final last = DateTime(m.year, m.month + 1, 0);
  final rows = await api.getVendorBills(
      from: _apiDate.format(m), to: _apiDate.format(last));
  return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

final vendorsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await api.getVendors();
  return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

double _n(Object? v) => v == null ? 0 : double.tryParse(v.toString()) ?? 0;

/// Purchase invoices from suppliers.
///
/// These are what make the GST input tax credit reports possible: a vendor bill
/// carries the supplier's GSTIN, their invoice number and date, and the
/// taxable/tax split, none of which a plain expense records. Lines can also
/// receive stock into an item, a size/variant or a raw material.
class VendorBillsScreen extends ConsumerWidget {
  const VendorBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(vendorBillMonthProvider);
    final billsAsync = ref.watch(vendorBillsProvider);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Builder(
        builder: (context) {
          // Full labels ("Create purchase list" + "Add purchase") overflow
          // past the screen edge on narrow phones; below that width, use a
          // shorter label instead of dropping it, so both FABs stay in one
          // row and still say what they do at a glance.
          final screenWidth = MediaQuery.of(context).size.width;
          final compact = screenWidth < 420;

          final purchaseListFab = FloatingActionButton.extended(
            heroTag: 'purchaseListFab',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchaseListScreen()),
            ),
            icon: const Icon(Icons.checklist_outlined),
            label: Text(compact
                ? context.l10n.purchaseListFabShort
                : context.l10n.purchaseListFabLong),
          );
          final addPurchaseFab = FloatingActionButton.extended(
            // Unique tag: a duplicate throws during a route transition when two
            // FABs briefly coexist.
            heroTag: 'vendorBillFab',
            onPressed: () => _openForm(context, ref, null),
            icon: const Icon(Icons.add),
            label: Text(compact
                ? context.l10n.purchaseFabShort
                : context.l10n.purchaseFabLong),
          );

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              purchaseListFab,
              const SizedBox(width: 12),
              addPurchaseFab,
            ],
          );
        },
      ),
      body: Column(children: [
        ShellAppBar(
          title: Text(context.l10n.purchasesTitle),
          // Each purchase lot's cost and profit — shops that maintain batches.
          actions: [
            if (ref.watch(batchTrackingProvider))
              IconButton(
                icon: const Icon(Icons.layers_outlined),
                tooltip: context.l10n.batchesTitle,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockBatchesScreen()),
                ),
              ),
          ],
        ),
        Expanded(
          child: Column(children: [
            _monthBar(context, ref, month, isCurrentMonth, billsAsync),
            Expanded(
              child: billsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => AppErrorWidget(
                    error: e,
                    onRetry: () => ref.invalidate(vendorBillsProvider)),
                data: (bills) => bills.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message: context.l10n.purchaseNoneThisMonth)
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(vendorBillsProvider),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: bills.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) =>
                              _billCard(context, ref, bills[i]),
                        ),
                      ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _monthBar(BuildContext context, WidgetRef ref, DateTime month,
      bool isCurrentMonth, AsyncValue<List<Map<String, dynamic>>> async) {
    final total = async.valueOrNull
            ?.fold<double>(0, (s, b) => s + _n(b['total'])) ??
        0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => ref.read(vendorBillMonthProvider.notifier).state =
              DateTime(month.year, month.month - 1, 1),
        ),
        Expanded(
          child: Column(children: [
            Text(DateFormat('MMMM yyyy').format(month),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            Text('Rs. ${_money.format(total)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrentMonth
              ? null
              : () => ref.read(vendorBillMonthProvider.notifier).state =
                  DateTime(month.year, month.month + 1, 1),
        ),
      ]),
    );
  }

  Widget _billCard(
      BuildContext context, WidgetRef ref, Map<String, dynamic> b) {
    final status = (b['payment_status'] ?? 'paid').toString();
    final statusType = status == 'paid'
        ? StatusType.success
        : status == 'partial'
            ? StatusType.info
            : StatusType.warning;
    return AppCard(
      onTap: () => _openForm(context, ref, b),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b['vendor_name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                '${b['invoice_number']} · '
                '${_dateFmt.format(DateTime.parse(b['invoice_date'].toString()))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              if ((b['vendor_gstin'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(b['vendor_gstin'].toString(),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Rs. ${_money.format(_n(b['total']))}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            StatusBadge(label: _statusLabel(context, status), status: statusType),
          ],
        ),
      ]),
    );
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'unpaid':
        return context.l10n.purchaseStatusUnpaid;
      case 'partial':
        return context.l10n.purchaseStatusPartial;
      default:
        return context.l10n.purchaseStatusPaid;
    }
  }

  Future<void> _openForm(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? record) async {
    // Flags are read ONCE here and passed in, matching the items form: the
    // form is a plain StatefulWidget and must not re-read providers mid-edit.
    final gstEnabled = ref.read(gstEnabledProvider);
    // The list endpoint returns headers only (no `lines`); the form needs the
    // full bill to prefill its line items, so fetch it by id first.
    if (record != null && record['lines'] is! List) {
      try {
        record = await api.getVendorBill(record['id'].toString());
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(api.sanitizeUiErrorMessage(e))));
        return;
      }
      if (!context.mounted) return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VendorBillFormScreen(
          record: record,
          gstEnabled: gstEnabled,
          onSaved: () {
            ref.invalidate(vendorBillsProvider);
            ref.invalidate(vendorsProvider);
          },
        ),
      ),
    );
  }
}

/// One editable line in the purchase form. Owns its controllers so they can be
/// disposed individually when a line is removed.
class _LineDraft {
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  final TextEditingController rate;
  final TextEditingController hsn;

  /// Scheme goods ("10 + 2 free"): received into stock, never charged.
  final TextEditingController free;

  /// The supplier's own wording for this line, when it came from a scanned
  /// bill. Saving a linked line teaches the server "this vendor's text means
  /// this item", so the next bill from them links itself.
  String? vendorText;

  /// Came from an AI scan: the next scan replaces it, and it is flagged while
  /// unlinked. [isCharge] marks the scan's "Other charges" line, which is
  /// meant to stay unlinked.
  bool fromScan = false;
  bool isCharge = false;

  /// Items this scanned line's wording resembles, for one-tap linking.
  List<StockTarget> suggestions = const [];

  /// Linked by the scan's AI item matching, not by the owner or a saved
  /// mapping — flagged so the owner checks it. Any re-link clears it.
  bool aiMatched = false;

  /// The quantity the bill's amount ÷ printed rate points to, when the scanned
  /// one disagrees — offered as a one-tap fix while the line's flags show.
  double? fixQty;

  /// What the scan flagged on this line (already localised). Shown only while
  /// the numbers are as the scan left them: once the owner edits any of them,
  /// they have looked at the line and the flags go.
  List<String> _scanWarnings = const [];
  String _warnedNumbers = '';
  String get _numbers => '${qty.text}|${price.text}|${rate.text}|${free.text}';
  List<String> get scanWarnings =>
      _numbers == _warnedNumbers ? _scanWarnings : const [];
  set scanWarnings(List<String> w) {
    _scanWarnings = w;
    _warnedNumbers = _numbers;
  }

  String? itemId;
  String? variantId;
  String? rawMaterialId;
  String? unit;

  /// The linked target's pack, and whether [qty] is typed in packs. The server
  /// only ever sees base units — see [quantity].
  String? packUnit;
  double? packSize;
  bool inPacks = false;

  /// Stock batch this line's stock goes into (shops that maintain batches):
  /// [batchId] = top up that existing batch (same rate only — the server
  /// checks), null = a new batch under the bill's batch no., or this line's
  /// own [batchNo] when one is typed in its batch sheet.
  String? batchId;
  String? batchCode;
  String? batchNo;

  /// Focus node for the item-name field; the autocomplete needs to own it.
  final FocusNode nameFocus = FocusNode();

  /// The name the line was linked under. If the user edits the text away
  /// from it, the link is dropped — the line no longer describes that item.
  String? _linkedName;

  _LineDraft({
    String name = '',
    String qty = '',
    String price = '',
    String rate = '',
    String hsn = '',
    String free = '',
    this.vendorText,
    this.itemId,
    this.variantId,
    this.rawMaterialId,
    this.unit,
  })  : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty),
        price = TextEditingController(text: price),
        rate = TextEditingController(text: rate),
        hsn = TextEditingController(text: hsn),
        free = TextEditingController(text: free) {
    _linkedName = isLinked ? this.name.text : null;
    this.name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (isLinked && name.text != _linkedName) unlink();
  }

  List<Listenable> get listenables => [name, qty, price, rate, free];

  void dispose() {
    name.removeListener(_onNameChanged);
    nameFocus.dispose();
    name.dispose();
    qty.dispose();
    price.dispose();
    rate.dispose();
    hsn.dispose();
    free.dispose();
  }

  /// Whether this line is tied to a stock target. Only linked lines move
  /// inventory on the server; a free-text line is a service/freight charge.
  bool get isLinked =>
      itemId != null || variantId != null || rawMaterialId != null;

  /// Ties the line to [t]: sets the single target id, the display name and
  /// unit, and pre-fills HSN / GST % from the item when the user hasn't typed
  /// them. The amount is never pre-filled — a purchase cost is not the
  /// sale price.
  void link(StockTarget t) {
    itemId = t.itemId;
    variantId = t.variantId;
    rawMaterialId = t.rawMaterialId;
    unit = t.unit;
    packUnit = t.packUnit;
    packSize = t.packSize;
    inPacks = false;
    aiMatched = false;
    batchId = batchCode = batchNo = null;
    _linkedName = t.name;
    name.text = t.name;
    if (hsn.text.trim().isEmpty && t.hsnCode != null) hsn.text = t.hsnCode!;
    if (rate.text.trim().isEmpty && t.taxRate != null) {
      rate.text = t.taxRate! % 1 == 0
          ? t.taxRate!.toInt().toString()
          : t.taxRate!.toString();
    }
  }

  /// Drops the stock link but keeps the typed name, so the line becomes a
  /// plain description line rather than vanishing.
  void unlink() {
    itemId = null;
    variantId = null;
    rawMaterialId = null;
    unit = null;
    packUnit = null;
    packSize = null;
    inPacks = false;
    aiMatched = false;
    batchId = batchCode = batchNo = null;
    _linkedName = null;
  }

  /// In base units: "2" typed in boxes of 15 is 30.
  double get quantity {
    final typed = double.tryParse(qty.text.trim()) ?? 0;
    return inPacks && packSize != null ? typed * packSize! : typed;
  }

  /// Free goods in base units, typed in the same unit/pack as [qty].
  double get freeQuantity {
    final typed = double.tryParse(free.text.trim()) ?? 0;
    return inPacks && packSize != null ? typed * packSize! : typed;
  }

  /// The user types the line's total amount, not a per-unit price — a vendor
  /// bill quotes "10 kg — Rs. 500", and dividing that by hand is a step the
  /// form can take instead.
  double get amount => double.tryParse(price.text.trim()) ?? 0;

  /// Derived for the server, which stores purchases per unit. A zero quantity
  /// can't yield a rate; the form's validator blocks saving in that state.
  double get unitPrice => quantity == 0 ? 0 : amount / quantity;
  double? get taxRate =>
      rate.text.trim().isEmpty ? null : double.tryParse(rate.text.trim());

  double get net => amount;
  double get tax => net * ((taxRate ?? 0) / 100);

  Map<String, dynamic> toJson() => {
        if (itemId != null) 'item_id': itemId,
        if (variantId != null) 'variant_id': variantId,
        if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
        'name': name.text.trim(),
        if (unit != null) 'unit': unit,
        'quantity': quantity,
        // Per PAID unit: free goods add stock, not cost.
        'unit_price': unitPrice,
        if (freeQuantity > 0) 'free_quantity': freeQuantity,
        if (taxRate != null) 'tax_rate': taxRate,
        if (hsn.text.trim().isNotEmpty) 'hsn_code': hsn.text.trim(),
        if (vendorText != null) 'vendor_text': vendorText,
        if (inPacks) 'in_packs': true,
        if (batchId != null) 'batch_id': batchId,
      };
}

class _QuickAddResult {
  final String name;
  final String unit;
  final double? price;
  final double? taxRate;
  const _QuickAddResult(
      {required this.name, required this.unit, this.price, this.taxRate});
}

/// Minimal "create it now" dialog for an item typed into a purchase line that
/// doesn't exist yet. Asks only what the server insists on (a sale price for
/// shop items) plus the unit; everything else can be filled in later from the
/// Items screen.
class _QuickAddDialog extends StatefulWidget {
  final String initialName;
  final bool isRestaurant;
  final bool gstEnabled;
  const _QuickAddDialog({
    required this.initialName,
    required this.isRestaurant,
    required this.gstEnabled,
  });

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  static const _itemUnits = [
    'piece', 'kg', 'g', 'litre', 'ml', 'metre', 'dozen', 'plate',
    'packet', 'box', 'bottle', 'pair', 'set', 'bundle', 'bag', 'sqft', 'ton',
    'quintal', 'roll',
  ];
  static const _materialUnits = ['piece', 'g', 'kg', 'ml', 'litre'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _price = TextEditingController();
  final _tax = TextEditingController();
  String _unit = 'piece';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _tax.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = widget.isRestaurant ? _materialUnits : _itemUnits;
    return AlertDialog(
      title: Text(widget.isRestaurant
          ? context.l10n.purchaseQuickAddRawMaterial
          : context.l10n.purchaseQuickAddItem),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(
            label: context.l10n.purchaseFieldName,
            controller: _name,
            capitalizeWords: true,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? context.l10n.purchaseNameRequired
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: InputDecoration(
                labelText: context.l10n.purchaseFieldUnit,
                border: const OutlineInputBorder()),
            items: [
              for (final u in units) DropdownMenuItem(value: u, child: Text(u)),
            ],
            onChanged: (v) => setState(() => _unit = v ?? 'piece'),
          ),
          if (!widget.isRestaurant) ...[
            const SizedBox(height: 12),
            AppTextField(
              label: context.l10n.purchaseFieldSalePrice,
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final p = double.tryParse((v ?? '').trim());
                return (p == null || p < 0)
                    ? context.l10n.purchaseSalePriceRequired
                    : null;
              },
            ),
            if (widget.gstEnabled) ...[
              const SizedBox(height: 12),
              AppTextField(
                label: context.l10n.purchaseFieldGstOptional,
                controller: _tax,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel)),
        TextButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _QuickAddResult(
                name: _name.text.trim(),
                unit: _unit,
                price: widget.isRestaurant
                    ? null
                    : double.parse(_price.text.trim()),
                taxRate: double.tryParse(_tax.text.trim()),
              ),
            );
          },
          child: Text(context.l10n.commonAdd),
        ),
      ],
    );
  }
}

/// Full-page form for creating or editing a purchase invoice.
///
/// A page rather than a bottom sheet: a purchase has a header, a variable
/// number of line items and a totals footer, which is far more than a sheet
/// comfortably holds — and the keyboard covering half a sheet makes the line
/// editor unusable on a phone.
class VendorBillFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? record;
  final bool gstEnabled;
  final VoidCallback onSaved;

  const VendorBillFormScreen({
    super.key,
    required this.record,
    required this.gstEnabled,
    required this.onSaved,
  });

  @override
  ConsumerState<VendorBillFormScreen> createState() =>
      _VendorBillFormScreenState();
}

class _VendorBillFormScreenState extends ConsumerState<VendorBillFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vendorCtrl;
  final _vendorFocus = FocusNode();
  late final TextEditingController _gstinCtrl;
  /// Vendors seen on past bills (name + GSTIN), for the vendor type-ahead.
  List<Map<String, dynamic>> _vendors = const [];
  late final TextEditingController _invoiceCtrl;
  /// The supplier's lot no. for every line that opens a new batch, typed once
  /// for the bill. A line's own lot (its batch sheet) wins. Batch shops only.
  final _billBatchCtrl = TextEditingController();
  /// Batch nos. used before (loaded on first need), and whether a batch sheet
  /// is already up — a second tap while one opens must not stack another.
  List<Map<String, dynamic>>? _batchCodes;
  bool _batchSheetOpen = false;
  late final TextEditingController _discountCtrl;
  /// Only asked for a part payment; the server sets paid / unpaid itself.
  late final TextEditingController _amountPaidCtrl;
  final List<_LineDraft> _lines = [];
  DateTime _invoiceDate = DateTime.now();
  String _paymentMode = 'cash';
  String _paymentStatus = 'paid';
  bool _interstate = false;
  bool _itcEligible = true;
  bool _reverseCharge = false;
  bool _saving = false;

  /// Printed round-off. Only a scan sets it (the form has no field for it);
  /// it is kept on edit so re-saving doesn't silently drop it.
  double _roundOff = 0;
  bool _dateTouched = false;

  /// AI bill scanning: whether this shop may scan ({enabled, used, limit}),
  /// and what the last scan read. [_scanId] ties the saved bill to its
  /// original file; [_scanBytes] is that file, shown while reviewing. The
  /// printed figures drive the live checks above Save; per-line flags live on
  /// each [_LineDraft].
  Map<String, dynamic>? _scanStatus;
  String? _scanId;
  Uint8List? _scanBytes;
  double? _scannedSubtotal;
  double? _scannedTax;
  double? _scannedTotal;
  /// Set when this vendor's invoice number is already recorded.
  String? _duplicateDate;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    // Each line's batch chip shows the lot it will get.
    _billBatchCtrl.addListener(() => setState(() {}));
    final r = widget.record;
    _vendorCtrl = TextEditingController(text: r?['vendor_name']?.toString() ?? '');
    _gstinCtrl = TextEditingController(text: r?['vendor_gstin']?.toString() ?? '');
    _invoiceCtrl =
        TextEditingController(text: r?['invoice_number']?.toString() ?? '');
    _discountCtrl = TextEditingController(
        text: r != null && _n(r['discount_amount']) > 0
            ? _n(r['discount_amount']).toStringAsFixed(2)
            : '');
    _amountPaidCtrl = TextEditingController(
        text: r != null && r['payment_status'] == 'partial'
            ? _n(r['amount_paid']).toStringAsFixed(2)
            : '');
    if (r != null) {
      _invoiceDate = DateTime.parse(r['invoice_date'].toString());
      _paymentMode = r['payment_mode']?.toString() ?? 'cash';
      _paymentStatus = r['payment_status']?.toString() ?? 'paid';
      _interstate = r['is_interstate'] == true;
      _itcEligible = r['itc_eligible'] != false;
      _reverseCharge = r['reverse_charge'] == true;
      _roundOff = _n(r['round_off']);
      _dateTouched = true;
      for (final l in (r['lines'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(l as Map);
        _lines.add(_LineDraft(
          name: m['item_name']?.toString() ?? '',
          qty: _n(m['quantity']).toString(),
          // Stored per unit, shown as the line's total — the inverse of the
          // division done on save.
          price: (_n(m['unit_price']) * _n(m['quantity'])).toStringAsFixed(2),
          rate: m['tax_rate'] == null ? '' : _n(m['tax_rate']).toString(),
          hsn: m['hsn_code']?.toString() ?? '',
          free: _n(m['free_quantity']) > 0 ? _qty(_n(m['free_quantity'])) : '',
          itemId: m['item_id']?.toString(),
          variantId: m['variant_id']?.toString(),
          rawMaterialId: m['raw_material_id']?.toString(),
          unit: m['unit']?.toString(),
        )
          ..batchId = m['batch_id']?.toString()
          ..batchCode = m['batch_code']?.toString());
      }
      // Typed batch nos. come back as each line's own, so a save never renames
      // them; when every line shares one, it shows as the bill's instead. An
      // automatic "B-0007" stays blank: blank keeps the name it has.
      final auto = RegExp(r'^B-\d{4,}$');
      for (final l in _lines) {
        final code = l.batchCode;
        if (code != null && !auto.hasMatch(code)) l.batchNo = code;
      }
      final codes = _lines.map((l) => l.batchCode).whereType<String>().toSet();
      if (codes.length == 1 && !auto.hasMatch(codes.first)) {
        _billBatchCtrl.text = codes.first;
        for (final l in _lines) {
          l.batchNo = null;
        }
      }
    }
    if (_lines.isEmpty) _lines.add(_LineDraft());
    // Loaded once; suggestions are a convenience, so a failure is silent.
    ref.read(vendorsProvider.future).then((v) {
      if (mounted) setState(() => _vendors = v);
    }).catchError((_) {});
    // Scanning is offered on new bills only, and only when the admin enabled
    // it for this shop; any failure here just leaves the button hidden.
    if (!_isEdit) {
      api.getPurchaseScanStatus().then((s) {
        if (mounted) setState(() => _scanStatus = s);
      }).catchError((_) {});
    }
  }

  Iterable<Map<String, dynamic>> _vendorSuggestions(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return const [];
    return _vendors.where(
        (v) => (v['name']?.toString() ?? '').toLowerCase().contains(t));
  }

  void _onVendorPicked(Map<String, dynamic> v) {
    _vendorCtrl.text = v['name']?.toString() ?? '';
    final gstin = v['gstin']?.toString().trim() ?? '';
    // Only fill a GSTIN when the vendor has one; never wipe what was typed.
    if (gstin.isNotEmpty) _gstinCtrl.text = gstin.toUpperCase();
  }

  Widget _vendorNameField() {
    return LayoutBuilder(builder: (context, constraints) {
      return RawAutocomplete<Map<String, dynamic>>(
        textEditingController: _vendorCtrl,
        focusNode: _vendorFocus,
        optionsBuilder: (v) => _vendorSuggestions(v.text),
        displayStringForOption: (v) => v['name']?.toString() ?? '',
        onSelected: _onVendorPicked,
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => AppTextField(
          label: context.l10n.purchaseFieldVendorName,
          controller: ctrl,
          focusNode: focus,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.l10n.purchaseVendorNameRequired
              : null,
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: SizedBox(
              width: constraints.maxWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final v = options.elementAt(i);
                    final gstin = v['gstin']?.toString().trim() ?? '';
                    return ListTile(
                      dense: true,
                      title: Text(v['name']?.toString() ?? ''),
                      subtitle: gstin.isNotEmpty
                          ? Text(gstin, style: const TextStyle(fontSize: 11))
                          : null,
                      onTap: () => onSelected(v),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  /// Everything a purchase line can be received into, for the current
  /// business. Reads (not watches) the providers: the form is a one-shot
  /// page and the lists are already loaded by the time it opens.
  List<StockTarget> _stockTargets() => buildStockTargets(
        isRestaurant: isRestaurantBusiness(ref.read(businessTypeProvider)),
        items: ref.read(itemsProvider).valueOrNull ?? const [],
        materials: ref.read(rawMaterialsProvider).valueOrNull ?? const [],
      );

  /// Marker id for the trailing "Add ... as a new item" suggestion. It is
  /// never sent to the server: selecting it opens the quick-add dialog and the
  /// line is linked to whatever that creates.
  static const _kAddNew = '__add_new__';

  bool get _isRestaurant =>
      isRestaurantBusiness(ref.read(businessTypeProvider));

  /// Suggestions for the item-name field: every stock target whose name
  /// contains what was typed. A sized item is listed once per size
  /// ("Tee (S)", "Tee (M)"), so typing the item name surfaces its variants.
  /// When nothing matches the typed name exactly, an "add new" row is
  /// appended so a first-time purchase can create the item on the spot.
  Iterable<StockTarget> _suggestions(String typed) {
    final name = typed.trim();
    final q = name.toLowerCase();
    if (q.isEmpty) return const Iterable.empty();
    final matches =
        _stockTargets().where((t) => t.name.toLowerCase().contains(q)).toList();
    final exact = matches.any((t) => t.name.toLowerCase() == q);
    if (!exact) {
      matches.add(StockTarget(name: name, unit: '', itemId: _kAddNew));
    }
    return matches;
  }

  /// Creates a new item (or raw material for restaurants) named [name] and
  /// returns it as a stock target, or null if the user cancelled / it failed.
  /// Stock starts at 0 when inventory is on so the purchase itself brings the
  /// count up — the whole point of adding it from here.
  Future<StockTarget?> _quickAdd(String name) async {
    final inventoryOn = ref.read(inventoryEnabledProvider);
    final result = await showDialog<_QuickAddResult>(
      context: context,
      builder: (_) => _QuickAddDialog(
        initialName: name,
        isRestaurant: _isRestaurant,
        gstEnabled: widget.gstEnabled,
      ),
    );
    if (result == null || !mounted) return null;
    try {
      if (_isRestaurant) {
        final m = await ref.read(rawMaterialsProvider.notifier).add({
          'name': result.name,
          'unit': result.unit,
          if (inventoryOn) 'stock_quantity': 0,
        });
        return StockTarget(
            name: m.name, unit: m.unit, currentStock: m.stockQuantity,
            rawMaterialId: m.id);
      }
      final it = await ref.read(itemsProvider.notifier).addItem({
        'name': result.name,
        'unit': result.unit,
        'price': result.price,
        if (result.taxRate != null) 'tax_rate': result.taxRate,
        if (inventoryOn) 'stock_quantity': 0,
      });
      return StockTarget(
          name: it.name, unit: it.unit, currentStock: it.stockQuantity,
          itemId: it.id, hsnCode: it.hsnCode, taxRate: it.taxRate);
    } catch (e) {
      if (mounted) _snack(api.sanitizeUiErrorMessage(e));
      return null;
    }
  }

  Future<void> _onSuggestionPicked(_LineDraft l, StockTarget t) async {
    if (t.itemId != _kAddNew) {
      setState(() => l.link(t));
      return;
    }
    final created = await _quickAdd(t.name);
    if (created == null || !mounted) return;
    setState(() {
      // The autocomplete only rebuilds its option list on a text change, and
      // the created item's name is exactly what was typed — so clear first,
      // then link (which sets the name). That forces a fresh option list, in
      // which the new item is now a real match and the "Add" row is gone.
      l.name.clear();
      l.link(created);
    });
    // Close the dropdown; the next natural step is the quantity field.
    l.nameFocus.unfocus();
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _vendorFocus.dispose();
    _gstinCtrl.dispose();
    _invoiceCtrl.dispose();
    _billBatchCtrl.dispose();
    _discountCtrl.dispose();
    _amountPaidCtrl.dispose();
    // Every per-line controller must be disposed or the sheet leaks them.
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wide enough to review a scanned bill next to the form it filled.
    final sideBySide =
        _scanBytes != null && MediaQuery.sizeOf(context).width >= 900;
    final form = _formBody();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: Text(_isEdit
              ? context.l10n.purchaseEditTitle
              : context.l10n.purchaseAddTitle),
          actions: [
            if (_scanStatus?['enabled'] == true) _scanAction(),
            if (_scanBytes != null && !sideBySide)
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: context.l10n.purchaseViewBill,
                onPressed: () => _showBill(_scanBytes!),
              )
            else if (_isEdit && widget.record!['has_attachment'] == true)
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: context.l10n.purchaseViewOriginal,
                onPressed: _saving ? null : _viewOriginal,
              ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: context.l10n.purchaseImportPdfTooltip,
              onPressed: _saving ? null : _importFromPdf,
            ),
            if (_isEdit)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                tooltip: context.l10n.commonDelete,
                onPressed: _saving ? null : _confirmDelete,
              ),
          ],
        ),
        Expanded(
          child: sideBySide
              ? Row(children: [
                  Expanded(
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: _BillView(
                          key: ObjectKey(_scanBytes), bytes: _scanBytes!),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: form),
                ])
              : form,
        ),
      ]),
    );
  }

  /// The whole-bill form, scrollable. Split out of [build] so a scanned bill
  /// can sit beside it on a wide screen.
  Widget _formBody() {
    return Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            _scanPrompt(),
            _vendorNameField(),
            const SizedBox(height: 12),
            AppTextField(
              label: context.l10n.purchaseFieldInvoiceNumber,
              controller: _invoiceCtrl,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.l10n.purchaseInvoiceNumberRequired
                  : null,
            ),
            const SizedBox(height: 12),
            _dateField(),
            if (ref.watch(batchTrackingProvider)) ...[
              const SizedBox(height: 12),
              AppTextField(
                label: context.l10n.purchaseBillBatchNo,
                controller: _billBatchCtrl,
                maxLength: 50,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: context.l10n.batchEarlierNos,
                  onPressed: _pickBillBatchNo,
                ),
              ),
            ],

            const SizedBox(height: 12),
            AppTextField(
              label: context.l10n.purchaseFieldVendorGstin,
              controller: _gstinCtrl,
              hint: '27AAAAA0000A1Z5',
              validator: (v) {
                final t = (v ?? '').trim().toUpperCase();
                if (t.isEmpty) return null;
                final ok = RegExp(
                        r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$')
                    .hasMatch(t);
                // A wrong GSTIN silently breaks GSTR-2B matching later, so
                // it is rejected at entry rather than at reconciliation.
                return ok ? null : context.l10n.purchaseGstinInvalid;
              },
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.purchaseGstinHelp,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _interstate,
              onChanged: (v) => setState(() => _interstate = v),
              title: Text(context.l10n.purchaseInterstate,
                  style: const TextStyle(fontSize: 13)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _itcEligible,
              onChanged: (v) => setState(() => _itcEligible = v),
              title: Text(context.l10n.purchaseItcClaimable,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(context.l10n.purchaseItcBlockedHint,
                  style: const TextStyle(fontSize: 11)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _reverseCharge,
              onChanged: (v) => setState(() => _reverseCharge = v),
              title: Text(context.l10n.purchaseReverseCharge,
                  style: const TextStyle(fontSize: 13)),
            ),

            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.purchaseItemsSection,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            if (!ref.watch(inventoryEnabledProvider)) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.purchaseInventoryOffHint,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ],
            for (var i = 0; i < _lines.length; i++) _lineEditor(i),
            const SizedBox(height: 12),
            // Below the lines, not above them: the button sits where the next
            // line will appear, so tapping it reads as continuing downward.
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                text: context.l10n.purchaseAddLine,
                icon: Icons.add,
                onPressed: () => setState(() => _lines.add(_LineDraft())),
              ),
            ),

            const SizedBox(height: 12),
            AppTextField(
              label: context.l10n.purchaseFieldDiscountOptional,
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _paymentRow(),
            if (_paymentStatus == 'partial') ...[
              const SizedBox(height: 12),
              AppTextField(
                label: context.l10n.purchaseFieldAmountPaid,
                controller: _amountPaidCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                // "Less than the total" is checked by the server.
                validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0
                    ? null
                    : context.l10n.expensesAmountInvalid,
              ),
            ],
            const SizedBox(height: 16),
            _totalsFooter(),
            const SizedBox(height: 16),
            PrimaryButton(
              text: _saving
                  ? context.l10n.commonSaving
                  : (_isEdit
                      ? context.l10n.purchaseUpdateButton
                      : context.l10n.purchaseSaveButton),
              onPressed: _saving ? null : _save,
            ),
              ]),
            ),
          );
  }

  /// On a fresh new bill, points at scanning while the form is still empty —
  /// the app-bar icon alone is easy to miss. Gone once anything is typed.
  Widget _scanPrompt() {
    final s = _scanStatus;
    if (_isEdit || _scanId != null || s?['enabled'] != true) {
      return const SizedBox.shrink();
    }
    final used = (s!['used'] as num?)?.toInt() ?? 0;
    final limit = (s['limit'] as num?)?.toInt() ?? 0;
    if (used >= limit) return const SizedBox.shrink();
    final first = _lines.first;
    return ListenableBuilder(
      listenable: Listenable.merge([_vendorCtrl, first.name]),
      builder: (context, _) {
        if (_vendorCtrl.text.trim().isNotEmpty ||
            _lines.length > 1 ||
            first.name.text.trim().isNotEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.document_scanner_outlined,
                color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.purchaseScanPromptTitle,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(context.l10n.purchaseScanPromptBody,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ]),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _scanBill,
              child: Text(context.l10n.purchaseScanPromptButton),
            ),
          ]),
        );
      },
    );
  }

  Widget _dateField() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _invoiceDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() {
            _invoiceDate = picked;
            _dateTouched = true;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                context.l10n.purchaseInvoiceDate(_dateFmt.format(_invoiceDate)),
                style: const TextStyle(fontSize: 14)),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    );
  }

  Widget _lineEditor(int i) {
    final l = _lines[i];
    // The border turns amber while the scan's flags on this line stand.
    return AnimatedBuilder(
      animation: Listenable.merge(l.listenables),
      builder: (_, child) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(
              color: l.scanWarnings.isEmpty
                  ? AppColors.border
                  : AppColors.warning),
        ),
        child: child,
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: _itemNameField(l)),
          if (_lines.length > 1)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.error),
              onPressed: () => setState(() {
                _lines.removeAt(i).dispose();
              }),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: AppTextField(
              label: context.l10n.purchaseFieldQty,
              controller: l.qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              // Tap to switch between the base unit and the pack.
              suffixIcon: l.packUnit != null && l.packSize != null
                  ? InkWell(
                      onTap: () => setState(() => l.inPacks = !l.inPacks),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UnitSuffix(unitShort(
                              l.inPacks ? l.packUnit! : (l.unit ?? 'piece'))),
                          const Icon(Icons.swap_vert,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                        ],
                      ),
                    )
                  : null,
              validator: (v) {
                final q = double.tryParse((v ?? '').trim());
                return (q == null || q <= 0)
                    ? context.l10n.purchaseInvalid
                    : null;
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppTextField(
              label: context.l10n.purchaseFieldAmount,
              controller: l.price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final p = double.tryParse((v ?? '').trim());
                return (p == null || p < 0)
                    ? context.l10n.purchaseInvalid
                    : null;
              },
            ),
          ),
          const SizedBox(width: 8),
          // Always offered, never required: a shop that bills without GST can
          // still buy from a registered vendor, and leaving this blank is how
          // a line says it carries no tax.
          Expanded(
            child: AppTextField(
              label: context.l10n.purchaseFieldGstOptional,
              controller: l.rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final r = double.tryParse(t);
                return (r == null || r < 0 || r > 100)
                    ? context.l10n.purchaseInvalid
                    : null;
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 2,
            child: AppTextField(
                label: context.l10n.purchaseFieldHsnOptional,
                controller: l.hsn),
          ),
          const SizedBox(width: 8),
          // Scheme goods: counted into stock, not into the line's cost.
          Expanded(
            child: AppTextField(
              label: context.l10n.purchaseFieldFreeQty,
              controller: l.free,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final f = double.tryParse(t);
                return (f == null || f < 0) ? context.l10n.purchaseInvalid : null;
              },
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // AppTextField exposes no onChanged, so the live line total tracks the
        // controllers directly.
        AnimatedBuilder(
          animation: Listenable.merge(l.listenables),
          builder: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Row(children: [
            // The chip tells the user this line will move inventory; it
            // disappears as soon as the name is edited away from the item.
            if (l.isLinked)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Text(
                  l.unit == null || l.unit!.isEmpty
                      ? context.l10n.purchaseUpdatesStock
                      : context.l10n.purchaseUpdatesStockUnit(
                          l.inPacks || l.freeQuantity > 0
                              ? '${formatQty(l.quantity + l.freeQuantity)} ${unitShort(l.unit!)}'
                              : unitShort(l.unit!)),
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.primary),
                ),
              )
            // A scanned line that isn't tied to an item saves as a plain
            // line: no stock moves. Easy to miss without saying so.
            else if (l.fromScan && !l.isCharge)
              Flexible(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(context.l10n.purchaseScanNotLinked,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textPrimary)),
                ),
              ),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              // The amount is what the vendor bills; this is the per-unit rate
              // it works out to, which is what actually reaches the server and
              // prices the stock.
              if (l.quantity > 0 && l.amount > 0)
                Text(
                  context.l10n.purchaseRatePerUnit(
                      _rate(l.unitPrice),
                      l.unit == null || l.unit!.isEmpty
                          ? context.l10n.purchaseUnitFallback
                          : unitShort(l.unit!)),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              // With GST off the line total would just echo the Amount the
              // user typed, so it only earns its place when tax is added on
              // top of it.
              if (l.tax > 0)
                Text(
                    context.l10n
                        .purchaseLineTotal(_money.format(l.net + l.tax)),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ]),
          // Which batch the stock goes into — only for shops that maintain
          // batches, and only on lines that move an item's or size's stock.
          if (ref.watch(batchTrackingProvider) &&
              (l.itemId != null || l.variantId != null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.layers_outlined,
                      size: 16, color: AppColors.primary),
                  label: Text(
                      context.l10n.batchChip(l.batchCode ??
                          (_lineBatchNo(l) == null
                              ? context.l10n.batchNew
                              : '${context.l10n.batchNew} · ${_lineBatchNo(l)}')),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary)),
                  onPressed: () => _pickPurchaseBatch(l),
                ),
              ),
            ),
          // The AI picked this item on its own: worth a glance before the
          // save moves stock and teaches the vendor mapping. Its own line, so
          // it is never squeezed by the rate column.
          if (l.isLinked && l.aiMatched)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(context.l10n.purchaseScanAiMatched,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary))),
              ]),
            ),
          // Items the supplier's wording resembles — one tap links the line,
          // and saving then remembers it for this vendor's next bill.
          if (l.fromScan && !l.isLinked && l.suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in l.suggestions)
                  // Styled like the "Updates stock" chip: the theme's chip
                  // defaults (outline border, uncoloured label) read as disabled.
                  ActionChip(
                    avatar: const Icon(Icons.link,
                        size: 16, color: AppColors.primary),
                    label: Text(context.l10n.purchaseScanLinkTo(t.name),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary)),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.small)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _onSuggestionPicked(l, t),
                  ),
              ]),
            ),
          for (final w in l.scanWarnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(w, style: const TextStyle(fontSize: 12))),
                  ]),
            ),
          // Nothing changes until the owner taps; the edit then clears the
          // line's flags like any other.
          if (l.fixQty != null && l.scanWarnings.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: Text(context.l10n.purchaseScanUseQty(_qty(l.fixQty!))),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => l.qty.text = _qty(l.fixQty!)),
              ),
            ),
              ]),
        ),
      ]),
    );
  }

  /// The item-name field with type-ahead. Suggestions come from stock; picking
  /// one links the line so the purchase receives stock. Typing a name that
  /// matches nothing is fine — it saves as a plain line (freight, service).
  Widget _itemNameField(_LineDraft l) {
    return LayoutBuilder(builder: (context, constraints) {
      return RawAutocomplete<StockTarget>(
        textEditingController: l.name,
        focusNode: l.nameFocus,
        optionsBuilder: (v) => _suggestions(v.text),
        displayStringForOption: (t) => t.name,
        onSelected: (t) => _onSuggestionPicked(l, t),
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => AppTextField(
          label: context.l10n.purchaseFieldItemName,
          controller: ctrl,
          focusNode: focus,
          capitalizeWords: true,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.l10n.purchaseItemNameRequired
              : null,
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: SizedBox(
              width: constraints.maxWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final t = options.elementAt(i);
                    if (t.itemId == _kAddNew) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.add_circle_outline,
                            color: AppColors.primary),
                        title: Text(
                          _isRestaurant
                              ? context.l10n.purchaseAddAsRawMaterial(t.name)
                              : context.l10n.purchaseAddAsItem(t.name),
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                        onTap: () => onSelected(t),
                      );
                    }
                    return ListTile(
                      dense: true,
                      title: Text(t.name),
                      subtitle: t.currentStock != null
                          ? Text(
                              context.l10n.purchaseInStock(
                                  _qty(t.currentStock!), unitShort(t.unit)),
                              style: const TextStyle(fontSize: 11))
                          : null,
                      onTap: () => onSelected(t),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  static String _qty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  Widget _paymentRow() {
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: _paymentMode,
          decoration: InputDecoration(
              labelText: context.l10n.purchaseFieldPaymentMode,
              border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem(
                value: 'cash', child: Text(context.l10n.paymentCash)),
            DropdownMenuItem(
                value: 'upi', child: Text(context.l10n.paymentUpi)),
            DropdownMenuItem(
                value: 'card', child: Text(context.l10n.paymentCard)),
            DropdownMenuItem(
                value: 'other', child: Text(context.l10n.paymentOther)),
          ],
          onChanged: (v) => setState(() => _paymentMode = v ?? 'cash'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: _paymentStatus,
          decoration: InputDecoration(
              labelText: context.l10n.purchaseFieldStatus,
              border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem(
                value: 'paid', child: Text(context.l10n.purchaseStatusPaid)),
            DropdownMenuItem(
                value: 'unpaid',
                child: Text(context.l10n.purchaseStatusUnpaid)),
            DropdownMenuItem(
                value: 'partial',
                child: Text(context.l10n.purchaseStatusPartial)),
          ],
          onChanged: (v) => setState(() => _paymentStatus = v ?? 'paid'),
        ),
      ),
    ]);
  }

  Widget _totalsFooter() {
    final listenables = <Listenable>[_discountCtrl];
    for (final l in _lines) {
      listenables.addAll(l.listenables);
    }
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (_, __) {
        final subtotal = _lines.fold<double>(0, (s, l) => s + l.net);
        final rawTax = _lines.fold<double>(0, (s, l) => s + l.tax);
        final discount = (double.tryParse(_discountCtrl.text.trim()) ?? 0)
            .clamp(0.0, subtotal)
            .toDouble();
        // Tax is charged on the discounted net, mirroring the server.
        final tax = subtotal > 0 ? rawTax * ((subtotal - discount) / subtotal) : 0.0;
        final total = subtotal - discount + tax + _roundOff;
        final totalsBox = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Column(children: [
            _kv(context.l10n.purchaseTaxableValue, subtotal),
            if (discount > 0) _kv(context.l10n.purchaseDiscount, -discount),
            if (tax > 0) _kv(_interstate ? 'IGST' : 'CGST + SGST', tax),
            if (_roundOff != 0) _kv(context.l10n.purchaseRoundOff, _roundOff),
            const Divider(height: 16),
            _kv(context.l10n.purchaseTotal, total, bold: true),
          ]),
        );
        if (_scanId == null) return totalsBox;
        // The bill's taxable value covers goods only; the scan's "Other
        // charges" line is outside it (same as checkDraft on the server).
        final goods = _lines
            .where((l) => !l.isCharge)
            .fold<double>(0, (s, l) => s + l.net);
        return Column(children: [
          totalsBox,
          const SizedBox(height: 12),
          _reviewBanner(_scanReviewNotes(goods, tax, total)),
        ]);
      },
    );
  }

  /// What a scanned bill needs checked, recomputed on every edit so each
  /// note clears as the owner fixes the lines: the printed taxable value, GST
  /// and total against what is entered now. Values are never adjusted to make
  /// these go away. Per-line flags are on the lines themselves.
  List<String> _scanReviewNotes(double goods, double tax, double total) {
    final l10n = context.l10n;
    String m(double v) => _money.format(v);
    bool off(double? printed, double entered) =>
        printed != null && (entered - printed).abs() > 1;
    return [
      if (off(_scannedSubtotal, goods))
        l10n.purchaseScanWarnSubtotal(m(_scannedSubtotal!), m(goods)),
      if (off(_scannedTax, tax))
        l10n.purchaseScanWarnTaxTotal(m(_scannedTax!), m(tax)),
      if (off(_scannedTotal, total))
        l10n.purchaseScanTotalMismatch(m(_scannedTotal!), m(total)),
    ];
  }

  /// Turns one of the server's per-line checks into text for that line.
  String? _lineWarning(Map w) {
    final l10n = context.l10n;
    switch (w['code']) {
      case 'line_quantity_missing':
        return l10n.purchaseScanWarnQtyMissing;
      case 'line_qty_mismatch':
        return l10n.purchaseScanWarnQtyMismatch(
            _qty(_n(w['printed'])), _qty(_n(w['computed'])));
      case 'line_rate_mismatch':
        final rate = _money.format(_n(w['rate']));
        return w['computed_qty'] is num
            ? l10n.purchaseScanWarnRateQty(rate, _qty(_n(w['computed_qty'])))
            : l10n.purchaseScanWarnRate(rate);
      case 'line_amount_missing':
        return l10n.purchaseScanWarnAmountMissing;
      case 'line_tax_mismatch':
        return l10n.purchaseScanWarnLineTax;
      case 'cgst_sgst_unequal':
        return l10n.purchaseScanWarnCgstSgst;
      case 'tax_type_mismatch':
        return l10n.purchaseScanWarnTaxType;
      case 'cess_not_supported':
        return l10n.purchaseScanWarnCess;
    }
    return null;
  }

  /// Always shown after a scan: how many scanned lines will move stock, a
  /// possible duplicate, then any live mismatches.
  Widget _reviewBanner(List<String> notes) {
    final scanned = _lines.where((l) => l.fromScan && !l.isCharge);
    final linked = scanned.where((l) => l.isLinked).length;
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded,
                size: 18, color: AppColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(context.l10n.purchaseScanReviewTitle,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          if (_duplicateDate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                  context.l10n.purchaseScanDuplicate(_dateFmt.format(
                      DateTime.tryParse(_duplicateDate!) ?? _invoiceDate)),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error)),
            ),
          if (scanned.isNotEmpty)
            Text(context.l10n.purchaseScanLinkedSummary(linked, scanned.length),
                style: const TextStyle(fontSize: 12)),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $n', style: const TextStyle(fontSize: 12)),
            ),
        ]),
      );
  }

  Widget _kv(String k, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Text('Rs. ${_money.format(v)}',
                style: TextStyle(
                    fontSize: bold ? 15 : 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
        ),
      );

  /// Adds imported lines below whatever is already in the form. A single blank
  /// starter line (still empty) is replaced rather than kept, so importing into
  /// a fresh form doesn't leave a stray empty row. Call inside setState.
  void _appendLines(List<_LineDraft> lines) {
    if (_lines.length == 1 &&
        _lines.single.name.text.trim().isEmpty &&
        !_lines.single.isLinked) {
      _lines.removeAt(0).dispose();
    }
    _lines.addAll(lines);
  }

  // ---------------------------------------------------------------------------
  // AI bill scanning — the server reads the bill into a DRAFT that fills this
  // form; nothing is saved until the owner reviews it and taps Save.
  // ---------------------------------------------------------------------------

  Widget _scanAction() {
    final used = (_scanStatus!['used'] as num?)?.toInt() ?? 0;
    final limit = (_scanStatus!['limit'] as num?)?.toInt() ?? 0;
    final full = used >= limit;
    return IconButton(
      icon: const Icon(Icons.document_scanner_outlined),
      tooltip: full
          ? context.l10n.purchaseScanLimitReached(used, limit)
          : context.l10n.purchaseScanTooltip,
      onPressed: _saving || full ? null : _scanBill,
    );
  }

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The bill's bytes: camera / gallery / file on a phone, a file elsewhere.
  Future<Uint8List?> _pickBill() async {
    var source = 'file';
    if (_isMobile) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(c.l10n.purchaseScanTakePhoto),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(c.l10n.purchaseScanChooseGallery),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(c.l10n.purchaseScanChooseFile),
              onTap: () => Navigator.pop(c, 'file'),
            ),
          ]),
        ),
      );
      if (picked == null) return null;
      source = picked;
    }
    if (source != 'file') {
      // 2000px wide keeps small bill print legible while staying well under
      // the 5 MB per-image limit.
      final x = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 85,
      );
      return x?.readAsBytes();
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final f = picked.files.single;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    // A phone photo copied to the PC is often over the server's 5 MB
    // per-image cap; shrink it the way the camera path does instead of
    // refusing it. PDFs go as they are.
    if (bytes.length > 4.5 * 1024 * 1024 &&
        _billType(bytes) != 'application/pdf') {
      return compressToJpeg(bytes, maxEdge: 2000, quality: 85);
    }
    return bytes;
  }

  /// The file's real type from its first bytes (the server checks the same
  /// way). Unknown types go as octet-stream and get the server's clear refusal.
  static String _billType(List<int> b) {
    bool at(int i, List<int> sig) =>
        b.length >= i + sig.length &&
        Iterable<int>.generate(sig.length).every((k) => b[i + k] == sig[k]);
    if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
    if (at(0, '%PDF-'.codeUnits)) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<void> _scanBill() async {
    Uint8List? bytes;
    try {
      bytes = await _pickBill();
    } catch (e) {
      if (mounted) _snack(context.l10n.purchaseFilePickerFailed('$e'));
      return;
    }
    if (bytes == null || !mounted) return;

    // _saving also disables Save, Import and Scan, so nothing double-submits.
    setState(() => _saving = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(c.l10n.purchaseScanReading)),
          ]),
        ),
      ),
    );
    Map<String, dynamic>? result;
    Object? error;
    try {
      result = await api.scanPurchaseBill(bytes, _billType(bytes));
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _saving = false);

    if (error != null) {
      // The server's message covers each case: not enabled (403), allowance
      // used (429), unreadable bill (502), not set up (503), bad file (400).
      _snack(api.sanitizeUiErrorMessage(error,
          fallback: context.l10n.purchaseScanNetworkError));
      api.getPurchaseScanStatus().then((s) {
        if (mounted) setState(() => _scanStatus = s);
      }).catchError((_) {});
      return;
    }
    _applyScan(result!, bytes);
  }

  /// The target the server named by id ({item_id | variant_id |
  /// raw_material_id}), or null when it isn't in this shop's list.
  static StockTarget? _targetById(List<StockTarget> targets, Object? ids) {
    if (ids is! Map) return null;
    bool same(String? a, Object? b) =>
        a != null && b != null && a.toLowerCase() == b.toString().toLowerCase();
    for (final t in targets) {
      if (same(t.itemId, ids['item_id']) ||
          same(t.variantId, ids['variant_id']) ||
          same(t.rawMaterialId, ids['raw_material_id'])) {
        return t;
      }
    }
    return null;
  }

  /// The server's match (a saved vendor mapping, or the AI's when it was
  /// sure) first; otherwise exactly ONE exact-name match. Several items with
  /// the same name are never guessed between.
  StockTarget? _matchTarget(List<StockTarget> targets, Map<String, dynamic> m) {
    final byId = _targetById(targets, m['match']);
    if (byId != null) return byId;
    final key = (m['name']?.toString() ?? '').trim().toLowerCase();
    final exact = targets.where((t) => t.name.toLowerCase() == key).toList();
    return exact.length == 1 ? exact.single : null;
  }

  void _fillIfEmpty(TextEditingController c, Object? value) {
    final v = value?.toString().trim() ?? '';
    if (c.text.trim().isEmpty && v.isNotEmpty) c.text = v;
  }

  /// The past vendor the scanned seller already is — same GSTIN, else the
  /// same name ignoring case and spacing — so a scan never starts a second
  /// "SHREE GANESH TRADERS" beside the saved "Shree Ganesh Traders".
  Map<String, dynamic>? _knownVendor(String? gstin, String? name) {
    String norm(Object? s) => (s ?? '')
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (norm(gstin).isNotEmpty) {
      final byGstin =
          _vendors.where((v) => norm(v['gstin']) == norm(gstin)).firstOrNull;
      if (byGstin != null) return byGstin;
    }
    if (norm(name).isEmpty) return null;
    return _vendors.where((v) => norm(v['name']) == norm(name)).firstOrNull;
  }

  /// Whether the bill's printed unit is [t]'s pack ("box"), so the scanned
  /// quantity counts packs, not pieces.
  static bool _isPackUnit(StockTarget t, Object? unit) {
    final u = unit?.toString().trim().toLowerCase() ?? '';
    final p = t.packUnit?.toLowerCase();
    return u.isNotEmpty &&
        t.packSize != null &&
        p != null &&
        (u == p || u == unitShort(p).toLowerCase());
  }

  void _applyScan(Map<String, dynamic> r, Uint8List bytes) {
    final draft = Map<String, dynamic>.from(r['draft'] as Map);
    final h = Map<String, dynamic>.from(draft['header'] as Map);
    final rows = draft['lines'] as List? ?? const [];
    final targets = _stockTargets();

    // Line indices in the server's warnings refer to [rows], so they are
    // pinned to their lines here, before anything can move them.
    final perLine = <int, List<String>>{};
    final fixQty = <int, double>{};
    String? duplicateDate;
    for (final w in (r['warnings'] as List? ?? const [])) {
      if (w is! Map) continue;
      if (w['code'] == 'duplicate_invoice') {
        duplicateDate = w['invoice_date']?.toString();
        continue;
      }
      final i = w['line'];
      final text = _lineWarning(w);
      if (i is num && text != null) (perLine[i.toInt()] ??= []).add(text);
      if (i is num && w['computed_qty'] is num) {
        fixQty[i.toInt()] = _n(w['computed_qty']);
      }
    }

    final lines = <_LineDraft>[];
    for (var i = 0; i < rows.length; i++) {
      final m = Map<String, dynamic>.from(rows[i] as Map);
      final line = _LineDraft(
        name: m['name']?.toString() ?? '',
        // Blank when the bill's quantity couldn't be read; the field's
        // validator then asks for it.
        qty: m['quantity'] == null ? '' : _qty(_n(m['quantity'])),
        // The taxable line value — exactly what this form's Amount field holds.
        // Left blank when the bill's amount couldn't be read.
        price: m['amount'] == null ? '' : _n(m['amount']).toStringAsFixed(2),
        rate: m['tax_rate'] == null ? '' : _qty(_n(m['tax_rate'])),
        hsn: m['hsn_code']?.toString() ?? '',
        free: _n(m['free_quantity']) > 0 ? _qty(_n(m['free_quantity'])) : '',
        vendorText: m['vendor_text']?.toString(),
      )..fromScan = true;
      final target = _matchTarget(targets, m);
      if (target != null) {
        line.link(target);
        final match = m['match'];
        final saved = match is Map && match['source'] != 'ai';
        // A saved mapping remembers whether this vendor sells it in packs
        // (boxes); without one, the bill's own unit says so.
        line.inPacks = saved
            ? match['in_packs'] == true && target.packSize != null
            : _isPackUnit(target, m['unit']);
        line.aiMatched = match is Map && match['source'] == 'ai';
      } else {
        // The AI's 50/50 choices when it had some; else items whose words the
        // supplier's wording shares.
        final choices = [
          for (final ids in (m['suggest'] as List? ?? const []))
            if (_targetById(targets, ids) case final t?) t,
        ];
        line.suggestions = choices.isNotEmpty
            ? choices
            : suggestStockTargets(targets, line.name.text);
      }
      // After link(): it may fill the GST %, which must not read as an edit.
      line.scanWarnings = perLine[i] ?? const [];
      line.fixQty = fixQty[i];
      lines.add(line);
    }
    final other = _n(h['other_charges']);
    if (other > 0) {
      lines.add(_LineDraft(
          name: context.l10n.purchaseScanOtherCharges,
          qty: '1',
          price: other.toStringAsFixed(2))
        ..fromScan = true
        ..isCharge = true);
    }

    final used = (r['scans_used'] as num?)?.toInt() ?? 0;
    final limit = (r['scans_limit'] as num?)?.toInt() ?? 0;
    final known = _knownVendor(
        h['vendor_gstin']?.toString(), h['vendor_name']?.toString());
    setState(() {
      // A second scan replaces the first one's lines; hand-typed lines stay.
      for (final l in _lines.where((l) => l.fromScan).toList()) {
        _lines.remove(l);
        l.dispose();
      }
      _scanId = r['scan_id']?.toString();
      _scanBytes = bytes;
      _scannedSubtotal = h['subtotal'] == null ? null : _n(h['subtotal']);
      _scannedTax = h['total_tax'] == null ? null : _n(h['total_tax']);
      _scannedTotal = h['total'] == null ? null : _n(h['total']);
      _duplicateDate = duplicateDate;
      _roundOff = _n(h['round_off']);
      // Header fields only fill what is still empty — never what was typed.
      _fillIfEmpty(_vendorCtrl, known?['name'] ?? h['vendor_name']);
      _fillIfEmpty(_gstinCtrl, h['vendor_gstin'] ?? known?['gstin']);
      _fillIfEmpty(_invoiceCtrl, h['invoice_number']);
      if (_n(h['discount_amount']) > 0) {
        _fillIfEmpty(_discountCtrl, _n(h['discount_amount']).toStringAsFixed(2));
      }
      final date = DateTime.tryParse(h['invoice_date']?.toString() ?? '');
      // The date picker only allows 2020..today; a misread date outside that
      // would crash it, so it is ignored instead.
      if (!_dateTouched &&
          date != null &&
          !date.isAfter(DateTime.now()) &&
          !date.isBefore(DateTime(2020))) {
        _invoiceDate = date;
      }
      if (h['is_interstate'] is bool) _interstate = h['is_interstate'] as bool;
      _appendLines(lines);
      if (_lines.isEmpty) _lines.add(_LineDraft());
      _scanStatus = {...?_scanStatus, 'used': used, 'limit': limit};
    });
    _snack(context.l10n.purchaseScanUsage(used, limit));
  }

  /// The original invoice this bill was scanned from.
  Future<void> _viewOriginal() async {
    final id = widget.record!['id'].toString();
    try {
      final bytes = Uint8List.fromList(await api.vendorBillAttachmentBytes(id));
      if (mounted) await _showBill(bytes);
    } catch (_) {
      if (mounted) _snack(context.l10n.purchaseOpenOriginalFailed);
    }
  }

  /// A bill full-screen and zoomable — for screens too narrow to show it
  /// beside the form, and for a saved bill's original.
  Future<void> _showBill(Uint8List bytes) => showDialog<void>(
        context: context,
        builder: (c) => Dialog.fullscreen(
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: c.l10n.commonClose,
                  onPressed: () => Navigator.pop(c),
                ),
              ),
              Expanded(child: _BillView(bytes: bytes)),
            ]),
          ),
        ),
      );

  /// Lets the user pick a purchase-list PDF (from purchase_list_screen.dart's
  /// export), recovers the item/quantity rows via text extraction, shows them
  /// for review/edit, then inserts them as blank-amount lines below whatever is
  /// already in the form — the user only has to type each item's amount.
  Future<void> _importFromPdf() async {
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
    } catch (e) {
      if (mounted) _snack(context.l10n.purchaseFilePickerFailed('$e'));
      return;
    }
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;

    List<ParsedPurchaseRow> parsed;
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      parsed = PurchaseListPdfImporter.parseBytes(bytes);
    } catch (e) {
      if (mounted) {
        _snack(context.l10n.purchasePdfReadFailed);
      }
      return;
    }
    if (parsed.isEmpty) {
      if (mounted) _snack(context.l10n.purchasePdfNoItems);
      return;
    }
    if (!mounted) return;

    final reviewed = await showModalBottomSheet<List<ParsedPurchaseRow>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PdfImportReviewSheet(rows: parsed),
    );
    if (reviewed == null || reviewed.isEmpty || !mounted) return;

    // The purchase-list PDF was generated from these same item names, so an
    // exact match re-links the row to its stock target and the purchase will
    // receive stock. Unmatched rows stay as free-text lines.
    final targets = _stockTargets();
    setState(() {
      final imported = <_LineDraft>[];
      for (final row in reviewed) {
        final line = _LineDraft(
          name: row.name,
          qty: row.quantity != null
              ? (row.quantity! % 1 == 0
                  ? row.quantity!.toInt().toString()
                  : row.quantity!.toString())
              : '',
          // The amount is deliberately left blank — the user fills in each item's
          // what each item cost; the PDF only carried a quantity to buy.
        );
        final match = findStockTargetByName(targets, row.name);
        if (match != null) line.link(match);
        imported.add(line);
      }
      _appendLines(imported);
    });
  }

  /// A saved/edited/deleted purchase moved stock on the server, so the cached
  /// item and raw-material lists (and the offline mirror they refresh) are
  /// stale until refetched.
  void _refreshStock() {
    if (!mounted) return;
    ref.invalidate(itemsProvider);
    ref.invalidate(rawMaterialsProvider);
  }

  Future<void> _confirmDelete() async {
    // Units already sold from this bill's batches (each batch counted once).
    final soldByBatch = <String, double>{};
    for (final l in (widget.record?['lines'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(l as Map);
      final id = m['batch_id']?.toString();
      if (id != null) soldByBatch[id] = _n(m['batch_sold']);
    }
    final sold = soldByBatch.values.fold<double>(0, (s, v) => s + v);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.purchaseDeleteTitle),
        content: Text(sold > 0
            ? '${context.l10n.purchaseDeleteBody}\n\n${context.l10n.purchaseDeleteSoldNote(formatQty(sold))}'
            : context.l10n.purchaseDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(context.l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(context.l10n.commonDelete,
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await api.deleteVendorBill(widget.record!['id'].toString());
      _refreshStock();
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(api.sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'vendor_name': _vendorCtrl.text.trim(),
        if (_gstinCtrl.text.trim().isNotEmpty)
          'vendor_gstin': _gstinCtrl.text.trim().toUpperCase(),
        'invoice_number': _invoiceCtrl.text.trim(),
        'invoice_date': _apiDate.format(_invoiceDate),
        'is_interstate': _interstate,
        'itc_eligible': _itcEligible,
        'reverse_charge': _reverseCharge,
        'payment_mode': _paymentMode,
        'payment_status': _paymentStatus,
        if (_paymentStatus == 'partial')
          'amount_paid': double.tryParse(_amountPaidCtrl.text.trim()) ?? 0,
        if (_discountCtrl.text.trim().isNotEmpty)
          'discount_amount': double.tryParse(_discountCtrl.text.trim()) ?? 0,
        if (_roundOff != 0) 'round_off': _roundOff,
        // Links the bill to its original file; the server checks it is ours.
        if (_scanId != null) 'scan_id': _scanId,
        'lines': _lines.map((l) {
          final j = l.toJson();
          // The line's batch no., else the bill's; none = automatic. Sent for
          // top-ups too: the server renames only this purchase's own batches.
          final no = _lineBatchNo(l);
          if (no != null) j['batch_no'] = no;
          return j;
        }).toList(),
      };
      if (_isEdit) {
        await api.updateVendorBill(widget.record!['id'].toString(), data);
      } else {
        await api.createVendorBill(data);
      }
      _refreshStock();
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(api.sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The batch no. a line's new batch gets: its own, else the bill's;
  /// null = the purchase's automatic one.
  String? _lineBatchNo(_LineDraft l) {
    final bill = _billBatchCtrl.text.trim();
    return l.batchNo ?? (bill.isEmpty ? null : bill);
  }

  /// New batch (under the bill's batch no., or one typed for this item) or an existing batch of
  /// this item to top up. The server refuses a top-up at a different rate.
  Future<void> _pickPurchaseBatch(_LineDraft l) async {
    if (_batchSheetOpen) return;
    _batchSheetOpen = true;
    try {
      await _pickPurchaseBatchSheet(l);
    } finally {
      _batchSheetOpen = false;
    }
  }

  /// Batch nos. used before; an empty list when they can't be loaded.
  Future<List<Map<String, dynamic>>> _earlierBatchNos() async {
    try {
      return _batchCodes ??= await api.getBatchCodes();
    } catch (_) {
      return const [];
    }
  }

  /// The bill's batch no. from the ones used before.
  Future<void> _pickBillBatchNo() async {
    if (_batchSheetOpen) return;
    _batchSheetOpen = true;
    try {
      final codes = await _earlierBatchNos();
      if (!mounted || codes.isEmpty) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              title: Text(context.l10n.batchEarlierNos,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final b in codes) _batchNoTile(b, () => Navigator.pop(c, '${b['code']}')),
          ]),
        ),
      );
      if (picked != null && mounted) _billBatchCtrl.text = picked;
    } finally {
      _batchSheetOpen = false;
    }
  }

  /// "B-001 — 5 items · 2026-11-16", marked when it still has stock.
  Widget _batchNoTile(Map<String, dynamic> b, VoidCallback onTap, {bool selected = false}) {
    final open = b['open'] == true;
    return ListTile(
      onTap: onTap,
      selected: selected,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: open ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Icon(Icons.layers_outlined,
            size: 20, color: open ? AppColors.primary : AppColors.textSecondary),
      ),
      title: Text('${b['code']}',
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Text('${context.l10n.batchItemCount('${b['items']}')} · ${b['received_date']}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppColors.primary)
          : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
    );
  }

  /// A small grey heading between groups in a batch sheet.
  Widget _sheetSection(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary)),
      );

  Future<void> _pickPurchaseBatchSheet(_LineDraft l) async {
    final l10n = context.l10n;
    var open = const <Map<String, dynamic>>[];
    final codesF = _earlierBatchNos();
    try {
      open = await api.getStockBatches(itemId: l.itemId, variantId: l.variantId);
    } catch (_) {
      // Offline or failed: a new batch is still possible.
    }
    final codes = await codesF;
    if (!mounted) return;
    // ponytail: not disposed — the sheet still paints it while closing; one
    // small controller per pick is left to the GC.
    final noCtrl = TextEditingController(text: _lineBatchNo(l) ?? '');
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SafeArea(
          child: ListView(shrinkWrap: true, children: [
            // Which item this is for — the sheet covers one line.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(l.name.text.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            ListTile(
              leading: Icon(l.batchId == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
                  color: AppColors.primary),
              title: Text(l10n.batchNew),
              onTap: () => Navigator.pop(c, {'new': true}),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: noCtrl,
                maxLength: 50,
                decoration: InputDecoration(
                    labelText: l10n.batchNoForItem,
                    border: const OutlineInputBorder()),
                onSubmitted: (_) => Navigator.pop(c, {'new': true}),
              ),
            ),
            // A batch no. used before: this item goes in under it (joining
            // its batch when the item and rate match).
            if (codes.isNotEmpty) ...[
              _sheetSection(l10n.batchEarlierNos),
              for (final b in codes)
                _batchNoTile(b, () => Navigator.pop(c, {'new': true, 'no': '${b['code']}'}),
                    selected: l.batchId == null && _lineBatchNo(l) == '${b['code']}'),
            ],
            if (open.isNotEmpty) _sheetSection(l10n.batchAddTo),
            for (final b in open)
              ListTile(
                leading: Icon(l.batchId == b['id']
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text('${b['code']}'),
                subtitle: Text(l10n.batchLeftCost(
                    formatQty(_n(b['remaining'])), _money.format(_n(b['unit_cost'])))),
                onTap: () => Navigator.pop(c, b),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final lot = (picked['no'] as String?) ?? noCtrl.text.trim();
    setState(() {
      if (picked['new'] == true) {
        l.batchId = l.batchCode = null;
        l.batchNo = lot.isEmpty || lot == _billBatchCtrl.text.trim() ? null : lot;
      } else {
        l.batchId = picked['id'].toString();
        l.batchCode = picked['code'].toString();
        l.batchNo = null;
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// A supplier bill, zoomable: a photo as it is, a PDF as one image per page
/// (rendered once, in-app — no temp file or outside viewer needed).
class _BillView extends StatefulWidget {
  final Uint8List bytes;

  const _BillView({super.key, required this.bytes});

  @override
  State<_BillView> createState() => _BillViewState();
}

class _BillViewState extends State<_BillView> {
  late final bool _isPdf =
      _VendorBillFormScreenState._billType(widget.bytes) == 'application/pdf';
  List<Uint8List>? _pages;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!_isPdf) return;
    // 150 dpi keeps small bill print readable when zoomed.
    Printing.raster(widget.bytes, dpi: 150)
        .asyncMap((page) => page.toPng())
        .toList()
        .then((pages) {
      if (mounted) setState(() => _pages = pages);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final failed = Center(child: Text(context.l10n.purchaseBillShowFailed));
    if (!_isPdf) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.memory(widget.bytes,
              errorBuilder: (_, __, ___) => failed),
        ),
      );
    }
    if (_failed) return failed;
    final pages = _pages;
    if (pages == null) return const Center(child: CircularProgressIndicator());
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: pages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) =>
          InteractiveViewer(maxScale: 6, child: Image.memory(pages[i])),
    );
  }
}

/// Review sheet shown after a purchase-list PDF is parsed. PDF text
/// extraction is not exact — a row might merge two lines, or its quantity
/// might not have been isolated — so every recovered row is editable and can
/// be excluded here, before anything reaches the purchase form.
class _PdfImportReviewSheet extends StatefulWidget {
  final List<ParsedPurchaseRow> rows;

  const _PdfImportReviewSheet({required this.rows});

  @override
  State<_PdfImportReviewSheet> createState() => _PdfImportReviewSheetState();
}

class _PdfImportReviewSheetState extends State<_PdfImportReviewSheet> {
  late final List<TextEditingController> _names;
  late final List<TextEditingController> _qtys;
  late final List<bool> _included;

  @override
  void initState() {
    super.initState();
    _names = widget.rows.map((r) => TextEditingController(text: r.name)).toList();
    _qtys = widget.rows
        .map((r) => TextEditingController(
            text: r.quantity == null
                ? ''
                : (r.quantity! % 1 == 0
                    ? r.quantity!.toInt().toString()
                    : r.quantity!.toString())))
        .toList();
    // A row with no isolated quantity starts unchecked — it needs the user's
    // attention before it's safe to bring into the form.
    _included = widget.rows.map((r) => r.quantity != null).toList();
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    for (final c in _qtys) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final result = <ParsedPurchaseRow>[];
    for (var i = 0; i < widget.rows.length; i++) {
      if (!_included[i]) continue;
      final name = _names[i].text.trim();
      if (name.isEmpty) continue;
      result.add(ParsedPurchaseRow(
        name: name,
        quantity: double.tryParse(_qtys[i].text.trim()),
      ));
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(
                  child: Text(context.l10n.purchaseReviewImportTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                context.l10n.purchaseReviewImportHint,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                itemCount: widget.rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _included[i],
                      onChanged: (v) =>
                          setState(() => _included[i] = v ?? false),
                    ),
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        label: context.l10n.purchaseReviewItem,
                        controller: _names[i],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppTextField(
                        label: context.l10n.purchaseFieldQty,
                        controller: _qtys[i],
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: context.l10n.purchaseReviewConfirm(
                      _included.where((v) => v).length),
                  onPressed: _confirm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
