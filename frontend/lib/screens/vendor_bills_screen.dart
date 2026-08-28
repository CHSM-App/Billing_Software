import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api.dart' as api;
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../services/purchase_list_pdf_import.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/stock_target_picker.dart';
import 'purchase_list_screen.dart';

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
        ShellAppBar(title: Text(context.l10n.purchasesTitle)),
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
  String? itemId;
  String? variantId;
  String? rawMaterialId;
  String? unit;

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
    this.itemId,
    this.variantId,
    this.rawMaterialId,
    this.unit,
  })  : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty),
        price = TextEditingController(text: price),
        rate = TextEditingController(text: rate),
        hsn = TextEditingController(text: hsn) {
    _linkedName = isLinked ? this.name.text : null;
    this.name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (isLinked && name.text != _linkedName) unlink();
  }

  List<Listenable> get listenables => [name, qty, price, rate];

  void dispose() {
    name.removeListener(_onNameChanged);
    nameFocus.dispose();
    name.dispose();
    qty.dispose();
    price.dispose();
    rate.dispose();
    hsn.dispose();
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
    _linkedName = null;
  }

  double get quantity => double.tryParse(qty.text.trim()) ?? 0;

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
        'unit_price': unitPrice,
        if (taxRate != null) 'tax_rate': taxRate,
        if (hsn.text.trim().isNotEmpty) 'hsn_code': hsn.text.trim(),
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
  late final TextEditingController _discountCtrl;
  final List<_LineDraft> _lines = [];
  DateTime _invoiceDate = DateTime.now();
  String _paymentMode = 'cash';
  String _paymentStatus = 'paid';
  bool _interstate = false;
  bool _itcEligible = true;
  bool _reverseCharge = false;
  bool _saving = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _vendorCtrl = TextEditingController(text: r?['vendor_name']?.toString() ?? '');
    _gstinCtrl = TextEditingController(text: r?['vendor_gstin']?.toString() ?? '');
    _invoiceCtrl =
        TextEditingController(text: r?['invoice_number']?.toString() ?? '');
    _discountCtrl = TextEditingController(
        text: r != null && _n(r['discount_amount']) > 0
            ? _n(r['discount_amount']).toStringAsFixed(2)
            : '');
    if (r != null) {
      _invoiceDate = DateTime.parse(r['invoice_date'].toString());
      _paymentMode = r['payment_mode']?.toString() ?? 'cash';
      _paymentStatus = r['payment_status']?.toString() ?? 'paid';
      _interstate = r['is_interstate'] == true;
      _itcEligible = r['itc_eligible'] != false;
      _reverseCharge = r['reverse_charge'] == true;
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
          itemId: m['item_id']?.toString(),
          variantId: m['variant_id']?.toString(),
          rawMaterialId: m['raw_material_id']?.toString(),
          unit: m['unit']?.toString(),
        ));
      }
    }
    if (_lines.isEmpty) _lines.add(_LineDraft());
    // Loaded once; suggestions are a convenience, so a failure is silent.
    ref.read(vendorsProvider.future).then((v) {
      if (mounted) setState(() => _vendors = v);
    }).catchError((_) {});
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
    _discountCtrl.dispose();
    // Every per-line controller must be disposed or the sheet leaks them.
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: Text(_isEdit
              ? context.l10n.purchaseEditTitle
              : context.l10n.purchaseAddTitle),
          actions: [
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
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ),
        ),
      ]),
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
        if (picked != null) setState(() => _invoiceDate = picked);
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
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
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
        AppTextField(
            label: context.l10n.purchaseFieldHsnOptional, controller: l.hsn),
        const SizedBox(height: 6),
        // AppTextField exposes no onChanged, so the live line total tracks the
        // controllers directly.
        AnimatedBuilder(
          animation: Listenable.merge(l.listenables),
          builder: (_, __) => Row(children: [
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
                      : context.l10n.purchaseUpdatesStockUnit(l.unit!),
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.primary),
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
                          : l.unit!),
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
                                  _qty(t.currentStock!), t.unit),
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
        final total = subtotal - discount + tax;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Column(children: [
            _kv(context.l10n.purchaseTaxableValue, subtotal),
            if (discount > 0) _kv(context.l10n.purchaseDiscount, -discount),
            if (tax > 0) _kv(_interstate ? 'IGST' : 'CGST + SGST', tax),
            const Divider(height: 16),
            _kv(context.l10n.purchaseTotal, total, bold: true),
          ]),
        );
      },
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
      // A single blank starter line (still empty) is replaced rather than
      // kept, so importing into a fresh form doesn't leave a stray empty row.
      if (_lines.length == 1 &&
          _lines.single.name.text.trim().isEmpty &&
          !_lines.single.isLinked) {
        _lines.removeAt(0).dispose();
      }
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
        _lines.add(line);
      }
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.purchaseDeleteTitle),
        content: Text(context.l10n.purchaseDeleteBody),
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
        if (_discountCtrl.text.trim().isNotEmpty)
          'discount_amount': double.tryParse(_discountCtrl.text.trim()) ?? 0,
        'lines': _lines.map((l) => l.toJson()).toList(),
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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
