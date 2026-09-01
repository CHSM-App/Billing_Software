import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../models/cart_entry.dart';
import '../utils/money.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/whatsapp_mark.dart';
import '../widgets/stock_target_picker.dart' show isRestaurantBusiness;
import '../widgets/skeletons.dart';
import '../services/printer_service.dart';
import '../services/receipt_output.dart';
import '../services/receipt_labels.dart';
import '../services/offline_service.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../storage.dart';
import '../main.dart' show rootMessengerKey;
import 'bill_preview_screen.dart';
import 'login_screen.dart';
import 'printer_setup_screen.dart';

extension _StringEx on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Reduce a stored phone to the local 10-digit form for display/editing in the
/// billing card. Customer self-orders store the phone in WhatsApp format
/// ("91XXXXXXXXXX", 12 digits with the India country code); the billing field
/// holds 10 digits. Strip a leading "91" so the field doesn't overflow its
/// 10-digit limit and silently drop the last two digits. Anything already 10
/// digits (or an unrecognised shape) is returned unchanged.
String _localPhoneDigits(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    return digits.substring(2);
  }
  return digits;
}

class HomeScreen extends ConsumerStatefulWidget {
  final String? tableId;
  final String? tableNumber;
  final String? activeBillId;
  /// In-flight bill fetch — navigation and fetch run in parallel so the screen
  /// opens instantly and the cart loads as soon as the response arrives.
  final Future<Bill?>? activeBillFuture;
  /// Called instead of [Navigator.pop] when a bill is finalized or saved in
  /// split-view mode. When null the default pop behaviour is used.
  final VoidCallback? onBillDone;

  const HomeScreen(
      {super.key, this.tableId, this.tableNumber, this.activeBillId,
      this.activeBillFuture, this.onBillDone});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String _selectedCategory = '';
  bool _showCustomerFields = true;
  String _paymentMode = 'cash';
  // Inline error shown inside the billing card when a credit bill is missing
  // the required customer name/phone. Cleared once both are provided.
  String? _creditError;
  // On phones the cart lives in a bottom sheet built by its own builder, which
  // a parent setState won't rebuild. Capture its setter so credit-error changes
  // also refresh the open sheet.
  StateSetter? _sheetSetState;

  // Outstanding credit ("previous due") for the currently-entered phone, looked
  // up as the cashier types a 10-digit number. When _settlePrevCredit is on and
  // the bill is finalized, these bill_ids are settled with the same mode.
  double _prevCreditDue = 0;
  List<String> _prevCreditBillIds = const [];
  bool _settlePrevCredit = false;
  String? _prevCreditPhone; // the phone the lookup result belongs to
  Timer? _prevCreditDebounce;
  // Previous credit bills that were just settled with the current bill — each
  // is printed as its OWN receipt (never merged) when the finalize action is
  // Print. Consumed and cleared by _autoPrint / _sendBillWhatsApp.
  List<Bill> _justSettledPrevBills = const [];
  bool _generatingBill = false;
  bool _savingDraft = false;
  bool _draftLoaded = false;

  // Search bar expand state
  bool _searchExpanded = false;
  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnim;
  final _searchFocus = FocusNode();

  final _searchController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _discountPctController = TextEditingController();
  final _discountAmtController = TextEditingController();
  bool _updatingDiscount = false;

  // Focus nodes — used to auto-scroll the field above the keyboard
  final _customerNameFocus = FocusNode();
  final _customerPhoneFocus = FocusNode();
  final _discountPctFocus = FocusNode();
  final _discountAmtFocus = FocusNode();

  // GlobalKeys — give Scrollable.ensureVisible a handle to each field's context
  final _customerNameKey = GlobalKey();
  final _customerPhoneKey = GlobalKey();

  // Past-customer autocomplete. One result list serves both fields: the search
  // matches name OR phone, so whichever the user is typing into, picking a
  // suggestion fills both.
  List<Map<String, dynamic>> _customerSuggestions = const [];
  Timer? _customerSearchDebounce;
  // Which field the open list belongs to ('name' | 'phone' | null = closed).
  String? _suggestFor;
  // Set while a suggestion is being applied, so the controller listeners that
  // fire during the write do not immediately re-open the list.
  bool _applyingSuggestion = false;
  final _discountPctKey = GlobalKey();
  final _discountAmtKey = GlobalKey();

  // Additional charges (delivery, packaging, service, ...) — one editable row
  // per charge. Mirrors the server cap in backend/src/charges.js.
  final List<_ChargeRow> _charges = [];
  static const _maxAdditionalCharges = 10;
  // Charge descriptions used on past bills, most-used first (server list,
  // cached on-device). Offered under whichever description field is focused.
  List<ChargeSuggestion> _chargeSuggestions = const [];
  _ChargeRow? _chargeSuggestRow;
  static const _maxChargeSuggestionsShown = 6;
  static const _maxChargeSuggestionsKept = 30;

  final _barcodeBuffer = StringBuffer();
  DateTime? _lastKeyTime;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle so we can re-check printer reachability on resume —
    // the user may have toggled Bluetooth or powered the printer off/on while
    // the app was backgrounded. See didChangeAppLifecycleState.
    WidgetsBinding.instance.addObserver(this);
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _searchAnim = CurvedAnimation(parent: _searchAnimCtrl, curve: Curves.easeInOut);
    _searchController.addListener(() => setState(() {}));
    _discountPctController.addListener(_onDiscountPctChanged);
    _discountAmtController.addListener(_onDiscountAmtChanged);
    // Clear the inline credit error as soon as both name + phone are present.
    _customerNameController.addListener(_maybeClearCreditError);
    _customerPhoneController.addListener(_maybeClearCreditError);

    _customerNameController.addListener(() => _onCustomerTyped('name'));
    _customerPhoneController.addListener(() => _onCustomerTyped('phone'));
    _customerNameFocus.addListener(_closeSuggestionsOnBlur);
    _customerPhoneFocus.addListener(_closeSuggestionsOnBlur);
    // Look up any previous credit for the entered phone (10-digit trigger).
    _customerPhoneController.addListener(_onPhoneChangedForCredit);
    // Auto-scroll focused field above the keyboard
    _customerNameFocus.addListener(() {
      if (_customerNameFocus.hasFocus) _ensureVisible(_customerNameKey);
    });
    _customerPhoneFocus.addListener(() {
      if (_customerPhoneFocus.hasFocus) _ensureVisible(_customerPhoneKey);
    });
    _discountPctFocus.addListener(() {
      if (_discountPctFocus.hasFocus) _ensureVisible(_discountPctKey);
    });
    _discountAmtFocus.addListener(() {
      if (_discountAmtFocus.hasFocus) _ensureVisible(_discountAmtKey);
    });
    if (widget.activeBillId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoadDraft());
    }
    // Silently refresh item prices/stock on open so the cache never goes stale
    // enough to warrant a warning. Keeps current items visible meanwhile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(itemsProvider.notifier).refreshInBackground();
    });
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    _loadChargeSuggestions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground: Bluetooth / the printer may have changed
    // while we were away, so re-run the reachability check. This is what makes
    // the Save↔Print button and the hint update in realtime.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(canPrintProvider);
    }
  }

  void _ensureVisible(GlobalKey key) {
    // Two frames: first applies viewInsets padding, second has final layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key.currentContext;
        if (ctx == null || !mounted) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _searchAnimCtrl.dispose();
    _searchFocus.dispose();
    _searchController.dispose();
    _customerSearchDebounce?.cancel();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _discountPctController.dispose();
    _discountAmtController.dispose();
    _customerNameFocus.dispose();
    _customerPhoneFocus.dispose();
    _discountPctFocus.dispose();
    _discountAmtFocus.dispose();
    for (final r in _charges) {
      r.dispose();
    }
    _prevCreditDebounce?.cancel();
    super.dispose();
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final hasBarcodeScanner = ref.read(hasBarcodeProvider);
    if (!hasBarcodeScanner) return false;

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus?.context != null) {
      bool isTextField = false;
      primaryFocus!.context!.visitAncestorElements((element) {
        if (element.widget is EditableText) {
          isTextField = true;
          return false;
        }
        return true;
      });
      if (isTextField) return false;
    }

    final now = DateTime.now();
    if (_lastKeyTime != null &&
        now.difference(_lastKeyTime!).inMilliseconds > 100) {
      _barcodeBuffer.clear();
    }
    _lastKeyTime = now;

    // Many USB HID scanners send Numpad Enter (not the main Enter) as the
    // suffix character, so accept both.
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _barcodeBuffer.toString().trim();
      _barcodeBuffer.clear();
      _lastKeyTime = null;
      if (code.isNotEmpty) {
        primaryFocus?.unfocus();
        _handleBarcodeScan(code);
      }
      return true;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      // Ignore control characters (CR/LF/tab) some scanners emit as a suffix;
      // only printable characters belong in the barcode buffer.
      final code = char.codeUnitAt(0);
      if (code >= 0x20) {
        _barcodeBuffer.write(char);
      }
      return true;
    }
    return false;
  }

  Future<void> _tryLoadDraft() async {
    if (_draftLoaded || widget.activeBillId == null) return;
    final itemsAsync = ref.read(itemsProvider);
    if (!itemsAsync.hasValue) {
      ref.listenManual(itemsProvider, (_, next) {
        if (next.hasValue && !_draftLoaded) _tryLoadDraft();
      });
      return;
    }
    _draftLoaded = true;
    try {
      // Await the in-flight fetch (started before navigation) or fall back to
      // a fresh network call if no future was provided.
      final bill = (widget.activeBillFuture != null
              ? await widget.activeBillFuture
              : null) ??
          Bill.fromJson(await getBill(widget.activeBillId!));
      final allItems = itemsAsync.value!;
      ref.read(cartProvider.notifier).loadFromBill(bill, allItems);
      if (mounted) {
        setState(() {
          _paymentMode = bill.paymentMode;
          if (bill.customerName != null) {
            _customerNameController.text = bill.customerName!;
            _showCustomerFields = true;
          }
          if (bill.customerPhone != null) {
            // Stored phones from QR self-orders are "91XXXXXXXXXX"; show the
            // local 10 digits so the 10-char field doesn't truncate them.
            _customerPhoneController.text =
                _localPhoneDigits(bill.customerPhone!);
            _showCustomerFields = true;
          }
          // Restore the saved discount. Setting the amount fires the listener,
          // which derives the matching percentage from the (now loaded) total.
          if (bill.discountAmount > 0) {
            _discountAmtController.text = bill.discountAmount.toStringAsFixed(2);
          }
          // Restore any additional charges saved on the draft.
          _restoreCharges(bill.additionalCharges);
        });
      }
    } catch (_) {}
  }

  List<Item> _filteredItems(List<Item> allItems) {
    final query = _searchController.text.toLowerCase();
    return allItems.where((item) {
      if (!item.isActive) return false;
      final matchesSearch =
          query.isEmpty || item.name.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategory.isEmpty || item.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  // ── Additional charges ─────────────────────────────────────────────────────
  //
  // Delivery, packaging, service charges and the like. They ride on top of the
  // taxed items: part of the bill total, outside the taxable base (no GST) and
  // never reduced by the discount — the same model the backend applies
  // (backend/src/charges.js), so on-device and server figures agree.

  /// A fresh row wired to rebuild the panel as it is typed into and to scroll
  /// itself above the keyboard when focused.
  _ChargeRow _newChargeRow() {
    final row = _ChargeRow();
    row.nameController.addListener(_onChargesChanged);
    row.amountController.addListener(_onChargesChanged);
    row.nameFocus.addListener(() {
      if (row.nameFocus.hasFocus) {
        _ensureVisible(row.key);
        _chargeSuggestRow = row;
      } else if (_chargeSuggestRow == row) {
        _chargeSuggestRow = null;
      }
      if (mounted) setState(() {});
      _sheetSetState?.call(() {});
    });
    row.amountFocus.addListener(() {
      if (row.amountFocus.hasFocus) _ensureVisible(row.key);
    });
    return row;
  }

  // ── Charge-description suggestions ─────────────────────────────────────────

  /// Show the cached list straight away, then refresh it from the server in
  /// the background (merging, so a name remembered on this device from an
  /// offline bill that hasn't synced yet is not lost).
  Future<void> _loadChargeSuggestions() async {
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty) return;
    try {
      final cached = await getCachedChargeSuggestions(businessId);
      if (cached != null && cached.isNotEmpty) {
        final list = (jsonDecode(cached) as List)
            .whereType<Map>()
            .map((m) => ChargeSuggestion.fromJson(Map<String, dynamic>.from(m)))
            .where((s) => s.name.isNotEmpty)
            .toList();
        if (mounted) setState(() => _chargeSuggestions = list);
      }
    } catch (_) {}
    try {
      final remote = await getChargeSuggestions();
      if (!mounted) return;
      _mergeChargeSuggestions(remote, businessId: businessId, persist: true);
    } catch (_) {
      // Offline / failed fetch: the cached list (if any) stays in force.
    }
  }

  /// Upserts [incoming] into the in-memory list (case-insensitive on name; the
  /// higher use count wins), re-sorts most-used first, caps the list and
  /// optionally writes it back to the device cache.
  void _mergeChargeSuggestions(List<ChargeSuggestion> incoming,
      {required String businessId, bool persist = false}) {
    final byKey = <String, ChargeSuggestion>{
      for (final s in _chargeSuggestions) s.name.toLowerCase(): s,
    };
    for (final s in incoming) {
      if (s.name.isEmpty) continue;
      final key = s.name.toLowerCase();
      final cur = byKey[key];
      byKey[key] = cur == null
          ? s
          : s.copyWith(uses: s.uses > cur.uses ? s.uses : cur.uses);
    }
    final merged = byKey.values.toList()
      ..sort((a, b) => b.uses.compareTo(a.uses));
    final capped = merged.take(_maxChargeSuggestionsKept).toList();
    if (mounted) setState(() => _chargeSuggestions = capped);
    _sheetSetState?.call(() {});
    if (persist) {
      unawaited(saveCachedChargeSuggestions(
          businessId, jsonEncode(capped.map((s) => s.toJson()).toList())));
    }
  }

  /// Remember the charges on the bill being held/settled right now, so the
  /// very next bill can offer them even before the server list refreshes
  /// (and while offline).
  Future<void> _rememberUsedCharges() async {
    final entries = _chargeEntries();
    if (entries.isEmpty) return;
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty || !mounted) return;
    final used = <String, ChargeSuggestion>{
      for (final s in _chargeSuggestions) s.name.toLowerCase(): s,
    };
    _mergeChargeSuggestions(
      [
        for (final c in entries)
          ChargeSuggestion(
            name: c.name,
            uses: (used[c.name.toLowerCase()]?.uses ?? 0) + 1,
          ),
      ],
      businessId: businessId,
      persist: true,
    );
  }

  /// Suggestions for [row]: those containing what has been typed so far (all
  /// of them when the field is still empty), minus the exact current text and
  /// anything already used on another row of this bill.
  List<ChargeSuggestion> _chargeSuggestionsFor(_ChargeRow row) {
    if (_chargeSuggestRow != row || _chargeSuggestions.isEmpty) return const [];
    final q = row.name.toLowerCase();
    final taken = {
      for (final r in _charges)
        if (r != row && r.name.isNotEmpty) r.name.toLowerCase(),
    };
    return _chargeSuggestions
        .where((s) {
          final n = s.name.toLowerCase();
          return n != q && !taken.contains(n) && (q.isEmpty || n.contains(q));
        })
        .take(_maxChargeSuggestionsShown)
        .toList();
  }

  /// Fill the description from a picked suggestion and move the cursor to the
  /// amount field. Only the description is suggested — the amount is always
  /// typed fresh for this bill.
  void _applyChargeSuggestion(_ChargeRow row, ChargeSuggestion s) {
    // Assign via `value` so the caret lands after the text (a bare `.text =`
    // leaves the selection at offset 0).
    row.nameController.value = TextEditingValue(
      text: s.name,
      selection: TextSelection.collapsed(offset: s.name.length),
    );
    _chargeSuggestRow = null;
    if (mounted) setState(() {});
    _sheetSetState?.call(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.amountFocus.requestFocus();
    });
  }

  /// Dropdown of past charge descriptions under the focused description field.
  Widget _chargeSuggestionList(_ChargeRow row) {
    final items = _chargeSuggestionsFor(row);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) {
          final s = items[i];
          return InkWell(
            // onTapDown, not onTap: the field losing focus would otherwise
            // dismiss the list before the tap completed.
            onTapDown: (_) => _applyChargeSuggestion(row, s),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.history,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _addChargeRow() {
    if (_charges.length >= _maxAdditionalCharges) return;
    final row = _newChargeRow();
    setState(() => _charges.add(row));
    _sheetSetState?.call(() {});
    // Land the cursor in the new description field so the cashier can type
    // straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.nameFocus.requestFocus();
    });
  }

  void _removeChargeRow(_ChargeRow row) {
    setState(() => _charges.remove(row));
    _sheetSetState?.call(() {});
    // Dispose only after the frame that drops its fields from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  /// Drops every charge row (bill settled / cart cleared / draft reopened).
  void _clearCharges() {
    if (_charges.isEmpty) return;
    final rows = List<_ChargeRow>.from(_charges);
    _charges.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in rows) {
        r.dispose();
      }
    });
  }

  void _onChargesChanged() {
    if (!mounted) return;
    setState(() {});
    _sheetSetState?.call(() {});
  }

  /// Rebuilds the rows from a saved bill (reopening a draft).
  void _restoreCharges(List<BillCharge> charges) {
    _clearCharges();
    for (final c in charges.take(_maxAdditionalCharges)) {
      final row = _newChargeRow();
      row.nameController.text = c.name;
      row.amountController.text = c.amount.toStringAsFixed(2);
      _charges.add(row);
    }
  }

  /// The charges that count: a description AND a positive amount. A row still
  /// being typed into stays out of the totals until both parts are there.
  List<BillCharge> _chargeEntries() => [
        for (final r in _charges)
          if (r.name.isNotEmpty && r.amount > 0)
            BillCharge(name: r.name, amount: r.amount),
      ];

  double _chargesTotal() => BillCharge.sum(_chargeEntries());

  List<Map<String, dynamic>> _chargesPayload() =>
      _chargeEntries().map((c) => c.toJson()).toList();

  /// A half-filled row (description without an amount, or the reverse) would
  /// silently drop off the bill — stop and ask the cashier to complete it.
  bool _validateCharges() {
    final incomplete = _charges.any((r) =>
        (r.name.isNotEmpty || r.amountController.text.trim().isNotEmpty) &&
        (r.name.isEmpty || r.amount <= 0));
    if (incomplete) {
      _showSnack(context.l10n.billingChargeIncomplete, isError: true);
      return false;
    }
    return true;
  }

  void _onDiscountPctChanged() {
    if (_updatingDiscount) return;
    // Discount is applied to the NET (pre-tax) subtotal — tax is then charged on
    // the discounted net. So percentages are of the subtotal, not the gross total.
    final net = ref.read(cartSubtotalProvider);
    final pct = double.tryParse(_discountPctController.text) ?? 0;
    _updatingDiscount = true;
    final amt = net > 0 && pct > 0 ? (net * pct / 100) : 0.0;
    _discountAmtController.text = amt > 0 ? amt.toStringAsFixed(2) : '';
    _updatingDiscount = false;
    setState(() {});
    _sheetSetState?.call(() {});
  }

  void _onDiscountAmtChanged() {
    if (_updatingDiscount) return;
    // Percentage is of the NET subtotal (see _onDiscountPctChanged).
    final net = ref.read(cartSubtotalProvider);
    final amt = double.tryParse(_discountAmtController.text) ?? 0;
    _updatingDiscount = true;
    final pct = net > 0 && amt > 0 ? (amt / net * 100) : 0.0;
    _discountPctController.text = pct > 0 ? pct.toStringAsFixed(2) : '';
    _updatingDiscount = false;
    setState(() {});
    _sheetSetState?.call(() {});
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    if (barcode.isEmpty) return;
    final l10n = context.l10n;
    try {
      final businessId = await getBusinessId();
      final cached = await OfflineService.instance
          .getBarcodeMatch(barcode, businessId ?? '');
      if (cached != null) {
        _addScannedItem(cached.item, cached.variant);
        return;
      }
      final data = await getItemByBarcode(barcode);
      final item = Item.fromJson(data);
      // A size (variant) barcode resolves to its parent item plus which size
      // matched — add that specific size so its price/label is used.
      final matchedVariantId = data['matched_variant_id'] as String?;
      final variant = matchedVariantId == null
          ? null
          : item.variants
              .where((v) => v.id == matchedVariantId)
              .firstOrNull;
      _addScannedItem(item, variant);
      // _animateCartBadge();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack(l10n.billingItemNotFoundBarcode(barcode), isError: true);
    }
  }

  /// Add a scanned item to the cart, enforcing the SAME size rule as tapping an
  /// item in the list: a variant item can never be billed at its base price.
  ///
  /// A scan resolves to a specific size only when a VARIANT barcode matched. An
  /// item-level barcode on a variant item is ambiguous — the scan says "Chicken
  /// 65", not which plate — so the size picker must open instead of silently
  /// adding the base price. Without this a scan billed Chicken 65 at its 230
  /// base price when the real sizes are half 180 / Full 280.
  void _addScannedItem(Item item, ItemVariant? variant) {
    if (variant == null && item.hasVariants) {
      _showVariantPicker(item);
      return;
    }
    ref.read(cartProvider.notifier).addItem(item, variant: variant);
  }

  List<Map<String, dynamic>> get _cartPayload {
    final cart = ref.read(cartProvider);
    return cart
        .map((e) => {
              'item_id': e.item.id,
              if (e.variant != null) 'variant_id': e.variant!.id,
              'quantity': e.quantity,
            })
        .toList();
  }

  Future<void> _clearCart({bool inSheet = false}) async {
    // If this is a table with an active draft, offer to release the table.
    if (widget.activeBillId != null) {
      final l10n = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.billingReleaseTableTitle),
          content: Text(l10n.billingReleaseTableBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel)),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.billingReleaseTable,
                  style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      // Capture the notifier before any pop disposes this screen's `ref`.
      final tablesNotifier = ref.read(tablesProvider.notifier);
      final tableId = widget.tableId;
      final billId = widget.activeBillId!;
      try {
        await voidBill(billId);
        ref.read(cartProvider.notifier).clear();
        _discountPctController.clear();
        _discountAmtController.clear();
        _clearCharges();
        // Optimistically free the table so the Tables screen updates instantly,
        // then reconcile with the server in the background.
        if (tableId != null) {
          tablesNotifier.applyTableReleased(tableId, billId: billId);
        }
        if (!mounted) return;
        // When invoked from the cart bottom sheet, pop the sheet first so the
        // following pop closes the billing screen (not the sheet) and the user
        // lands back on the now-updated Tables list.
        if (inSheet) Navigator.pop(context);
        Navigator.pop(context); // close the billing screen
        unawaited(tablesNotifier.refreshSilently());
      } on ApiException catch (e) {
        _showSnack(e.message, isError: true);
      } catch (_) {
        _showSnack(l10n.billingReleaseTableFailed, isError: true);
      }
    } else {
      ref.read(cartProvider.notifier).clear();
      _discountPctController.clear();
      _discountAmtController.clear();
      _clearCharges();
    }
  }

  /// Parking an unfinished cart means different things in the two trades, so
  /// the button says what the user would say. A restaurant is holding a live
  /// order for a table; a shop is setting a bill aside while the customer
  /// fetches one more thing. "Draft" fit neither.
  String _parkLabel(AppLocalizations l10n) =>
      isRestaurantBusiness(ref.read(businessTypeProvider))
          ? l10n.billingSaveDraft
          : l10n.billingHoldBill;

  /// Confirms what parking actually achieved, which differs by trade AND by
  /// connectivity.
  ///
  /// A restaurant draft is broadcast to the kitchen queue the moment the server
  /// accepts it, so "sent to the kitchen" is the outcome the user cares about —
  /// but only once it has reached the server. Offline the bill is still sitting
  /// in the local queue, so promising the kitchen has it would be a lie the
  /// cook would discover before the cashier did.
  String _parkedMessage(AppLocalizations l10n, {required bool online}) {
    final restaurant = isRestaurantBusiness(ref.read(businessTypeProvider));
    if (restaurant) {
      return online ? l10n.billingDraftSaved : l10n.billingDraftSavedOffline;
    }
    return online ? l10n.billingBillHeld : l10n.billingBillHeldOffline;
  }

  /// What the customer actually hands over: the same figure the totals box
  /// shows as Net Payable. The settle button prints it, so it must be derived
  /// exactly as the summary derives it — discount reduces the taxable base,
  /// round-off applies to this bill alone, and a previous due is folded in only
  /// when the cashier chose to clear it here.
  double _netPayable() {
    final subtotal = ref.read(cartSubtotalProvider);
    final tax = ref.read(cartTaxProvider);
    final discountAmt = (double.tryParse(_discountAmtController.text) ?? 0.0)
        .clamp(0.0, subtotal);
    final effectiveTax =
        subtotal > 0 ? tax * (subtotal - discountAmt) / subtotal : 0.0;
    // Additional charges are part of the total (untaxed, undiscounted).
    final total = subtotal + effectiveTax + _chargesTotal();
    final roundOff =
        computeRoundOff(total - discountAmt, ref.read(roundOffEnabledProvider));
    final prevDue = _settlePrevCredit ? _prevCreditDue : 0.0;
    return total - discountAmt + roundOff + prevDue;
  }

  /// Queues a brand-new draft locally while offline and shows it optimistically.
  /// Mirrors [_generateBillOffline] but stores it in the offline_drafts queue
  /// (status:'draft') so it syncs to POST /bills on reconnect. Only called when
  /// [widget.activeBillId] is null (a fresh draft, not an edit of a synced one).
  Future<void> _saveDraftOffline(List<CartEntry> cart) async {
    final l10n = context.l10n;
    if (_savingDraft) return;
    setState(() => _savingDraft = true);
    try {
      final businessId = await getBusinessId() ?? '';
      final userId = await getUserId() ?? '';
      // Offline drafts share the finalized-bill scheme: 'INV-<deviceTag>-####'
      // (device tag keeps it globally unique across devices; kept as-is on sync).
      final draftNumber = await nextOfflineBillNumber();

      double subtotal = 0;
      double taxAmount = 0;
      // GST off → tax ignored entirely, even for items with a leftover tax_rate.
      // Same rule as the finalize path, so reopening this draft to bill it can
      // never resurrect tax the order card doesn't show.
      final gstEnabled = ref.read(gstEnabledProvider);
      final lineItems = cart.map((e) {
        // lineNet/lineTax back out the tax from an MRP (tax-inclusive) price,
        // so unit_price sent to the server is always the NET rate — matching
        // resolveNetPriceAndRate in routes/bills.js and keeping an offline bill
        // identical to the one the server would have computed.
        final lineSub = e.lineNet(gstEnabled);
        final taxRate = gstEnabled ? e.item.taxRate : null;
        final lineTax = e.lineTax(gstEnabled);
        subtotal += lineSub;
        taxAmount += lineTax;
        return {
          'item_id': e.item.id,
          'variant_id': e.variant?.id,
          'item_name': e.displayName,
          'quantity': e.quantity,
          'unit_price': e.netPrice(gstEnabled),
          'tax_rate': taxRate,
          'line_total': double.parse((lineSub + lineTax).toStringAsFixed(2)),
        };
      }).toList();
      // Discount applies to the NET subtotal; tax is charged on the discounted
      // net. Clamp the discount to the subtotal and scale the tax accordingly so
      // the stored figures match what the customer is shown and pays.
      final discountAmt =
          (double.tryParse(_discountAmtController.text) ?? 0.0)
              .clamp(0.0, subtotal);
      if (subtotal > 0) {
        taxAmount = double.parse(
            (taxAmount * (subtotal - discountAmt) / subtotal).toStringAsFixed(2));
      }
      // Additional charges sit on top of the taxed items: in the total, but
      // outside the tax base and untouched by the discount (same as the server).
      final charges = _chargeEntries();
      final chargesTotal = BillCharge.sum(charges);
      final total = double.parse(
          (subtotal + taxAmount + chargesTotal).toStringAsFixed(2));
      final customerName = _customerNameController.text.trim().nullIfEmpty;
      final customerPhone = _customerPhoneController.text.trim().nullIfEmpty;
      final tableId = widget.tableId;

      final queued = await OfflineService.instance.queueOfflineDraft({
        'business_id': businessId,
        'user_id': userId,
        'table_id': tableId,
        'table_number': widget.tableNumber,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmt,
        'charges_amount': chargesTotal,
        'additional_charges':
            charges.isEmpty ? null : BillCharge.encode(charges),
        'total': total,
        'payment_mode': _paymentMode,
        'items_json': jsonEncode(lineItems),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final localId = queued.localId;

      // Build an optimistic Bill so a table draft can be reopened offline from
      // the tables cache, and so the Open Orders queue can show it immediately.
      final localBill = Bill(
        id: localId,
        businessId: businessId,
        billNumber: draftNumber,
        tableId: tableId,
        tableNumber: widget.tableNumber,
        customerName: customerName,
        customerPhone: customerPhone,
        subtotal: subtotal,
        taxAmount: taxAmount,
        discountAmount: discountAmt,
        chargesAmount: chargesTotal,
        additionalCharges: charges,
        total: total,
        paymentMode: _paymentMode,
        status: 'draft',
        createdByUserId: userId,
        createdAt: DateTime.now(),
        items: lineItems
            .map((li) => BillItem(
                  id: li['item_id'] as String,
                  billId: localId,
                  itemId: li['item_id'] as String,
                  variantId: li['variant_id'] as String?,
                  itemName: li['item_name'] as String,
                  quantity: (li['quantity'] as double),
                  unitPrice: (li['unit_price'] as double),
                  taxRate: li['tax_rate'] as double?,
                  lineTotal: (li['line_total'] as double),
                ))
            .toList(),
      );

      if (tableId != null) {
        ref.read(tablesProvider.notifier).applyDraftSaved(tableId, bill: localBill);
      } else {
        ref.read(openDraftsProvider.notifier).addLocalDraft(localBill);
      }
      if (!mounted) return;
      _showSnack(_parkedMessage(l10n, online: false));

      if (widget.onBillDone != null) {
        widget.onBillDone!();
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        ref.read(cartProvider.notifier).clear();
        _customerNameController.clear();
        _customerPhoneController.clear();
        _discountPctController.clear();
        _discountAmtController.clear();
        _clearCharges();
        if (mounted) setState(() => _savingDraft = false);
      }
    } catch (e) {
      final msg = e is ApiException ? e.message : l10n.billingSaveFailed;
      _showSnack(msg, isError: true);
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _saveDraft() async {
    final l10n = context.l10n;
    if (_blockedUnsyncedLocalDraft()) return;
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack(l10n.billingAddAtLeastOneItemFirst, isError: true);
      return;
    }
    if (!_validateCustomerPhone()) return;
    if (!_validateCharges()) return;
    // Remember these descriptions for next time's suggestions (best-effort).
    unawaited(_rememberUsedCharges());

    // Offline: a brand-new draft is queued locally and synced on reconnect.
    // Editing an existing (already-synced) draft still needs the server, since
    // its items live under a real bill id there — keep that path online-only.
    final isOnline = ref.read(connectivityProvider);
    if (!isOnline) {
      if (widget.activeBillId != null) {
        _showSnack(l10n.billingDraftPendingSync, isError: true);
        return;
      }
      await _saveDraftOffline(cart);
      return;
    }
    if (_savingDraft) return; // guard against a double-tap before we pop
    setState(() => _savingDraft = true);

    // Snapshot everything the network call needs before we close the screen.
    final payload = _cartPayload;
    final activeBillId = widget.activeBillId;
    final tableId = widget.tableId;
    // Persist any customer details entered on the draft so they survive the
    // save and pre-fill when the order is reopened.
    final customerName = _customerNameController.text.trim().nullIfEmpty;
    final customerPhone = _customerPhoneController.text.trim().nullIfEmpty;
    // Persist the discount too, so reopening the draft keeps it (was previously
    // dropped — the draft saved with no discount).
    final discountAmount =
        double.tryParse(_discountAmtController.text.trim()) ?? 0.0;
    // Additional charges likewise — always sent on an edit so that removing
    // every charge clears them on the draft rather than leaving stale ones.
    final additionalCharges = _chargesPayload();
    // Capture the notifiers NOW. After Navigator.pop this ConsumerState is
    // disposed and its `ref` becomes defunct — using it for the background
    // reconcile would silently no-op (this was why the table never updated).
    final tablesNotifier = ref.read(tablesProvider.notifier);
    final openDraftsNotifier = ref.read(openDraftsProvider.notifier);

    // ── Optimistic UI ────────────────────────────────────────────────────────
    // Flip the table to "occupied" locally and close the billing screen
    // immediately. The actual API call runs in the background and the tables
    // list reconciles with the server when it returns. This removes the
    // save→close→refresh wait the user was seeing.
    if (tableId != null) {
      tablesNotifier.applyDraftSaved(tableId, billId: activeBillId);
    }
    _showSnack(_parkedMessage(l10n, online: true));
    if (widget.onBillDone != null) {
      widget.onBillDone!();
    } else if (Navigator.canPop(context)) {
      // Pushed as a table draft or reopened from Open Orders — pop back.
      Navigator.pop(context);
    } else {
      // Root Billing tab in the shell (nothing to pop). Saving from here creates
      // a table-less "open order": clear the cart so the screen is ready for the
      // next order, and let the Open Orders tab surface the saved draft.
      ref.read(cartProvider.notifier).clear();
      _discountPctController.clear();
      _discountAmtController.clear();
      _clearCharges();
      // This screen stays alive (nothing was popped), so reset the saving flag
      // ourselves — otherwise the park-order FAB spins forever.
      if (mounted) setState(() => _savingDraft = false);
    }

    // ── Background persistence + reconcile ───────────────────────────────────
    // Uses the captured notifier (not `ref`) so it survives this screen's
    // disposal after the pop above.
    unawaited(() async {
      try {
        final Map<String, dynamic> result;
        if (activeBillId != null) {
          result = await updateBillItems(
            activeBillId,
            payload,
            customerName: customerName,
            customerPhone: customerPhone,
            discountAmount: discountAmount,
            additionalCharges: additionalCharges,
          );
        } else {
          result = await createBill({
            'items': payload,
            'table_id': tableId,
            'payment_mode': _paymentMode,
            'status': 'draft',
            if (customerName != null) 'customer_name': customerName,
            if (customerPhone != null) 'customer_phone': customerPhone,
            if (discountAmount > 0) 'discount_amount': discountAmount,
            if (additionalCharges.isNotEmpty)
              'additional_charges': additionalCharges,
          });
        }
        // The draft is now on the server — nudge the Kitchen screen to refresh
        // so this order appears immediately, without waiting on an FCM push.
        NotificationService.instance.pingKitchen();
        if (tableId != null) {
          // Cache the authoritative bill (with its real id + items) and flip the
          // table right away, so re-tapping the table pre-selects the draft
          // instantly instead of waiting for the full tables refetch below.
          final bill = Bill.fromJson(result);
          tablesNotifier.applyDraftSaved(tableId, bill: bill);
          // Pull the authoritative table state + bill cache. Silent — no spinner.
          await tablesNotifier.refreshSilently();
        } else {
          // Table-less "open order": now that the write has COMMITTED, refresh the
          // Open Orders queue so the new/updated draft appears there. (Doing this
          // before the commit — as before — raced the write and returned stale
          // data, which is why the page looked empty until a manual refresh.)
          await openDraftsNotifier.refreshSilently();
        }
      } catch (e) {
        // The save failed after we already closed the screen — undo the
        // optimistic change by reloading the true server state and warn.
        if (tableId != null) {
          await tablesNotifier.refreshSilently();
        } else {
          await openDraftsNotifier.refreshSilently();
        }
        final msg = e is ApiException ? e.message : l10n.billingSaveFailed;
        _showGlobalSnack(msg, isError: true);
      }
    }());
  }

  /// A reopened draft whose id is still a local queue id ("LOCAL-…") has not
  /// synced to the server yet, so it has no real bill id to finalize or edit
  /// against. Block those actions and tell the user to reconnect. Returns true
  /// if the action should be blocked.
  bool _blockedUnsyncedLocalDraft() {
    if (widget.activeBillId?.startsWith('LOCAL-') ?? false) {
      _showSnack(context.l10n.billingDraftPendingSync, isError: true);
      return true;
    }
    return false;
  }

  Future<void> _generateBill({void Function(Bill)? onBillReady}) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack(context.l10n.billingAddAtLeastOneItem, isError: true);
      return;
    }
    if (!_validateCustomerPhone()) return;
    if (!_validateCharges()) return;
    // Remember these descriptions for next time's suggestions (best-effort).
    unawaited(_rememberUsedCharges());
    if (!_validateCreditCustomer()) return;

    // Finalizing an OFFLINE draft ('LOCAL-…'): the draft only exists in this
    // device's queue, so there is no server bill to finalize against.
    //   • Offline  → convert it to an offline finalized bill locally and delete
    //     the draft row (otherwise the order stays stuck in Open Orders as
    //     "still saving").
    //   • Online   → block: it must sync to the server first, then be finalized
    //     online against its real bill id.
    // Only table-less (Open Orders) drafts are finalized offline here; an
    // offline table draft keeps the existing path so its table state stays
    // consistent (finalizing a table order offline is handled via the Tables
    // flow, not this retail branch).
    final localDraftId = widget.activeBillId;
    final isLocalDraft =
        (localDraftId?.startsWith('LOCAL-') ?? false) && widget.tableId == null;
    if (isLocalDraft) {
      final isOnline = ref.read(connectivityProvider);
      if (isOnline) {
        _showSnack(context.l10n.billingDraftPendingSync, isError: true);
        return;
      }
      await _finalizeLocalDraftOffline(localDraftId!, cart,
          onBillReady: onBillReady);
      return;
    }

    if (widget.activeBillId != null || widget.tableId != null) {
      // Table / synced-draft billing — always online
      await _generateBillOnline(cart, onBillReady: onBillReady);
      return;
    }
    // Retail billing — online when connected, offline when not.
    //
    // The connectivity flag is only a HINT: it starts optimistically "online"
    // and flips to offline only after a request has already failed. So on the
    // FIRST bill after the network drops it can still read "online". We therefore
    // (1) go offline immediately when the flag already says offline, and
    // (2) if an online attempt hits a NetworkException, transparently fall back
    //     to offline billing instead of showing "check connection".
    final isOnline = ref.read(connectivityProvider);
    if (!isOnline) {
      await _billOfflineAndSync(cart, onBillReady: onBillReady);
      return;
    }
    try {
      await _generateBillOnline(cart, onBillReady: onBillReady);
    } on NetworkException {
      // Network dropped mid-request: the connectivity notifier is now offline.
      // Re-bill offline so the sale is never lost. Retail online billing creates
      // then finalizes a fresh bill, so a network failure means nothing was
      // committed server-side — safe to redo locally.
      await _billOfflineAndSync(cart, onBillReady: onBillReady);
    } on ApiException catch (e) {
      // Server responded but is broken (5xx — e.g. its database is down). The
      // internet is fine, but the sale would be lost — so fall back to offline
      // billing and let it sync when the server recovers, same as a network
      // outage. (4xx errors — stock conflict, validation — are handled inside
      // _generateBillOnline and never reach here.)
      if (e.statusCode >= 500) {
        if (mounted) {
          _showSnack(context.l10n.billingServerErrorSavedOffline, isError: true);
        }
        await _billOfflineAndSync(cart, onBillReady: onBillReady);
      } else {
        rethrow;
      }
    }
  }

  /// Queue the bill offline and kick a background sync. Shared by the "already
  /// offline" and "went offline mid-request" paths.
  Future<void> _billOfflineAndSync(List<CartEntry> cart,
      {void Function(Bill)? onBillReady}) async {
    await _generateBillOffline(cart, onBillReady: onBillReady);
    unawaited(SyncService.instance.syncAll().then((_) {
      ref.invalidate(reportProvider);
    }));
  }

  /// Finalize an offline draft ('LOCAL-…') while still offline: bill it locally
  /// (which queues a finalized offline bill + triggers sync), then delete the
  /// draft row so it stops appearing in Open Orders. Both the queued draft and
  /// the queued bill carry the same items; dropping the draft avoids it syncing
  /// as a duplicate later. If offline billing fails, the draft is left intact so
  /// nothing is lost.
  Future<void> _finalizeLocalDraftOffline(String draftId, List<CartEntry> cart,
      {void Function(Bill)? onBillReady}) async {
    var billed = false;
    await _billOfflineAndSync(cart, onBillReady: (bill) {
      billed = true;
      // Preserve the plain-bill navigation: _generateBillOffline only calls
      // _navigateAfterBill when no onBillReady is given, but we always pass one
      // (to observe success), so replicate that navigation here.
      if (onBillReady != null) {
        onBillReady(bill);
      } else {
        _navigateAfterBill();
      }
    });
    if (!billed) return; // offline billing errored — keep the draft
    await OfflineService.instance.deleteDraft(draftId);
    ref.read(openDraftsProvider.notifier).removeLocalDraft(draftId);
  }

  Future<void> _generateBillAndPrint() async {
    // For thermal sizes, verify a printer is configured BEFORE generating the
    // bill — otherwise it would finalize + clear the cart, then the print would
    // silently fail and the order would be lost. PDF sizes (A5/A4) don't need a
    // thermal printer (they open the OS print dialog), so skip the check there.
    final pdfSelected = await ReceiptOutput.isPdfSelected();
    if (!pdfSelected) {
      final printer = await PrinterService.instance.getActivePrinter();
      if (printer == null) {
        if (mounted) {
          _showSnack(context.l10n.historyNoPrinterConfigured, isError: true);
        }
        return;
      }
    }
    await _generateBill(onBillReady: (bill) {
      _navigateAfterBill();
      _autoPrint(bill);
    });
  }

  /// Opens the printer setup page, then refreshes the active-printer state so
  /// the finalize card immediately reflects a newly connected printer (Save →
  /// Print, hint disappears).
  Future<void> _openPrinterSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
    );
    ref.invalidate(canPrintProvider);
  }

  Future<void> _generateBillAndWhatsApp() async {
    await _generateBill(onBillReady: (bill) {
      _navigateAfterBill();
      _sendBillWhatsApp(bill);
    });
  }

  /// Park the unfinished cart. Wrapped so the row and the wide layout share one
  /// call: the sheet must close FIRST, or _saveDraft's own Navigator.pop closes
  /// the sheet instead of the billing screen and the user lands in the wrong
  /// place.
  void _park({required bool inSheet}) {
    if (inSheet) Navigator.pop(context);
    _saveDraft();
  }

  /// Settle the bill. [print] defaults to whatever the printer can do; passing
  /// false is the long-press escape hatch — settle deliberately without a slip
  /// even though a printer is connected.
  ///
  /// Every settle path runs the credit guard first, so no finish can bypass the
  /// name/phone a credit bill requires.
  void _settle({required bool inSheet, bool? withReceipt}) {
    if (!_validateCreditCustomer()) return;
    final canPrint = ref.read(printReadyProvider);
    final wantsPrint = (withReceipt ?? true) && canPrint;
    if (inSheet) Navigator.pop(context);
    if (wantsPrint) {
      _generateBillAndPrint();
    } else {
      _generateBill(onBillReady: (_) {
        _navigateAfterBill();
        // Say it out loud: a deliberate skip and a failed print look identical
        // otherwise, and the cashier needs to know no slip is coming.
        if (withReceipt == false && canPrint) {
          _showSnack(context.l10n.billingSettleOnlyDone);
        }
      });
    }
  }

  /// Settle, then hand the bill to WhatsApp. Not a share — this finalizes the
  /// sale exactly as [_settle] does, which is why its tile is captioned and
  /// coloured as a money action rather than as a share icon.
  void _settleWhatsApp({required bool inSheet}) {
    // Both guards run BEFORE anything is finalized: a missing phone must not
    // leave a settled bill with nowhere to send it.
    if (!_validateCreditCustomer()) return;
    if (!_ensureCustomerPhoneForWhatsApp()) return;
    if (inSheet) Navigator.pop(context);
    _generateBillAndWhatsApp();
  }


  /// True when a customer phone is present. Otherwise it reveals and focuses the
  /// customer-phone field (and warns) so the user can add it — WhatsApp needs a
  /// number and we must NOT finalize/clear the bill without one.
  bool _ensureCustomerPhoneForWhatsApp() {
    if (_customerPhoneController.text.trim().isNotEmpty) return true;
    setState(() => _showCustomerFields = true);
    _showSnack(context.l10n.billingWhatsappNeedsPhone, isError: true);
    // Focus after the frame so the (possibly just-expanded) field is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureVisible(_customerPhoneKey);
      _customerPhoneFocus.requestFocus();
    });
    return false;
  }

  /// Validates the customer phone: it may be empty (optional), but if entered it
  /// must be exactly 10 digits. On failure it reveals/focuses the field, warns,
  /// and returns false so callers abort the save/generate.
  bool _validateCustomerPhone() {
    final phone = _customerPhoneController.text.trim();
    if (phone.isEmpty) return true;
    if (RegExp(r'^\d{10}$').hasMatch(phone)) return true;
    setState(() => _showCustomerFields = true);
    _showSnack(context.l10n.billingPhoneInvalid, isError: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureVisible(_customerPhoneKey);
      _customerPhoneFocus.requestFocus();
    });
    return false;
  }

  /// Updates the inline credit error and rebuilds both the inline card (parent)
  /// and, if open, the phone bottom sheet.
  void _setCreditError(String? msg) {
    setState(() => _creditError = msg);
    _sheetSetState?.call(() {});
  }

  /// Debounced reaction to phone edits: when a full 10-digit number is entered,
  /// look up that customer's outstanding credit; clear the banner otherwise.
  // ---------------------------------------------------------------------------
  // Past-customer autocomplete
  // ---------------------------------------------------------------------------

  /// Debounced search as the user types into either customer field.
  void _onCustomerTyped(String field) {
    // Ignore the controller writes we make ourselves when filling a suggestion.
    if (_applyingSuggestion) return;
    // Only the focused field drives the list; the other is being written
    // programmatically, or is simply not in play.
    final focused = field == 'name'
        ? _customerNameFocus.hasFocus
        : _customerPhoneFocus.hasFocus;
    if (!focused) return;

    final q = (field == 'name'
            ? _customerNameController.text
            : _customerPhoneController.text)
        .trim();

    _customerSearchDebounce?.cancel();

    if (q.length < 2) {
      if (_customerSuggestions.isNotEmpty || _suggestFor != null) {
        setState(() {
          _customerSuggestions = const [];
          _suggestFor = null;
        });
        _sheetSetState?.call(() {});
      }
      return;
    }

    _customerSearchDebounce = Timer(
        const Duration(milliseconds: 300), () => _searchCustomers(q, field));
  }

  Future<void> _searchCustomers(String q, String field) async {
    try {
      final rows = await searchCustomers(q);
      if (!mounted) return;
      // The user may have typed on, or moved fields, while this was in flight.
      final current = (field == 'name'
              ? _customerNameController.text
              : _customerPhoneController.text)
          .trim();
      if (current != q) return;
      setState(() {
        _customerSuggestions = rows;
        _suggestFor = rows.isEmpty ? null : field;
      });
      _sheetSetState?.call(() {});
    } catch (_) {
      // A failed lookup must never block billing - just show no suggestions.
      if (!mounted) return;
      setState(() {
        _customerSuggestions = const [];
        _suggestFor = null;
      });
      _sheetSetState?.call(() {});
    }
  }

  /// Fill BOTH fields from a picked suggestion, whichever field was typed in.
  ///
  /// Picking "Ramesh" from the name list must bring his number along, and
  /// picking a number must bring the name — the whole point of the list is to
  /// recover a customer you already have, not just to complete one field.
  void _applyCustomerSuggestion(Map<String, dynamic> c) {
    // Kill the in-flight search first: it was started by the keystrokes that
    // opened this list, and letting it land would reopen the dropdown over the
    // values we are about to write.
    _customerSearchDebounce?.cancel();

    final name = (c['customer_name'] ?? '').toString().trim();
    final phone = (c['customer_phone'] ?? '').toString();
    // Strip any country prefix: the field accepts 10 digits only, and a stored
    // "918262878298" would otherwise be cut to the wrong number.
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final localPhone =
        digits.length > 10 ? digits.substring(digits.length - 10) : digits;

    _applyingSuggestion = true;
    // Assign via `value` so the caret lands after the text; a bare `.text =`
    // leaves the selection at offset 0, and the next keystroke would insert
    // in front of the name.
    if (name.isNotEmpty) {
      _customerNameController.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }
    if (localPhone.isNotEmpty) {
      _customerPhoneController.value = TextEditingValue(
        text: localPhone,
        selection: TextSelection.collapsed(offset: localPhone.length),
      );
    }
    _applyingSuggestion = false;

    _customerSuggestions = const [];
    _suggestFor = null;
    // Both hosts must repaint: the panel owns the fields in the wide layout,
    // while in the bottom sheet they are rebuilt by the sheet's own builder.
    if (mounted) setState(() {});
    _sheetSetState?.call(() {});

    // A complete number means the previous-credit lookup should run for it.
    _onPhoneChangedForCredit();
    FocusScope.of(context).unfocus();
  }

  void _closeSuggestionsOnBlur() {
    if (_customerNameFocus.hasFocus || _customerPhoneFocus.hasFocus) return;
    if (_suggestFor == null && _customerSuggestions.isEmpty) return;
    setState(() {
      _customerSuggestions = const [];
      _suggestFor = null;
    });
    _sheetSetState?.call(() {});
  }

  /// Dropdown of matching past customers, shown under whichever field is being
  /// typed into. Each row carries the name AND the number, so a repeat customer
  /// stays identifiable when several share a name.
  Widget _customerSuggestionList(String field) {
    if (_suggestFor != field || _customerSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _customerSuggestions.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) {
          final c = _customerSuggestions[i];
          final name = (c['customer_name'] ?? '').toString();
          final phone = (c['customer_phone'] ?? '').toString();
          final visits = int.tryParse('${c['visits'] ?? 0}') ?? 0;
          return InkWell(
            // onTapDown, not onTap: the field losing focus would otherwise
            // dismiss the list before the tap completed.
            onTapDown: (_) => _applyCustomerSuggestion(c),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.history,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? phone : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      if (name.isNotEmpty)
                        Text(phone,
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (visits > 1)
                  Text('$visits visits',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _onPhoneChangedForCredit() {
    final phone = _customerPhoneController.text.trim();
    _prevCreditDebounce?.cancel();

    // Not a complete number (or changed away): drop any stale banner.
    if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
      if (_prevCreditDue > 0 || _prevCreditPhone != null) {
        setState(() {
          _prevCreditDue = 0;
          _prevCreditBillIds = const [];
          _prevCreditPhone = null;
          _settlePrevCredit = false;
        });
        _sheetSetState?.call(() {});
      }
      return;
    }

    // Already have this phone's result — nothing to do.
    if (_prevCreditPhone == phone) return;

    _prevCreditDebounce = Timer(const Duration(milliseconds: 400),
        () => _lookupPrevCredit(phone));
  }

  Future<void> _lookupPrevCredit(String phone) async {
    try {
      final summary = await getCreditSummary(phone);
      // The user may have edited the phone while the request was in flight.
      if (!mounted || _customerPhoneController.text.trim() != phone) return;
      final due = double.tryParse('${summary['outstanding'] ?? 0}') ?? 0.0;
      final ids = (summary['bill_ids'] as List?)?.cast<String>() ?? const [];
      setState(() {
        _prevCreditPhone = phone;
        _prevCreditDue = due;
        _prevCreditBillIds = ids;
        // Default the toggle off; the cashier opts in per bill.
        _settlePrevCredit = false;
      });
      _sheetSetState?.call(() {});
    } catch (_) {
      // Best-effort: a failed lookup just means no banner. Don't disrupt billing.
    }
  }

  /// Clears the inline credit error once both name + phone are filled in, so
  /// the message disappears as the user completes the fields.
  void _maybeClearCreditError() {
    if (_creditError == null) return;
    if (_customerNameController.text.trim().isNotEmpty &&
        _customerPhoneController.text.trim().isNotEmpty) {
      _setCreditError(null);
    }
  }

  /// A credit (udhaari) bill must identify the debtor: name + phone are
  /// mandatory. Reveals and focuses the customer fields if either is missing.
  bool _validateCreditCustomer() {
    if (_paymentMode != 'credit') {
      if (_creditError != null) _setCreditError(null);
      return true;
    }
    final name = _customerNameController.text.trim();
    final phone = _customerPhoneController.text.trim();
    if (name.isNotEmpty && phone.isNotEmpty) {
      if (_creditError != null) _setCreditError(null);
      return true;
    }
    // Show the message inline inside the card (not a snackbar), and reveal +
    // focus the missing field without closing the billing card.
    _showCustomerFields = true;
    _setCreditError(context.l10n.billingCreditCustomerRequired);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = name.isEmpty ? _customerNameKey : _customerPhoneKey;
      _ensureVisible(key);
      (name.isEmpty ? _customerNameFocus : _customerPhoneFocus).requestFocus();
    });
    return false;
  }

  /// Called the moment a bill is durably saved (server-confirmed, or written to
  /// the offline queue) — BEFORE any printing.
  ///
  /// Confirms the save with a global snackbar and refreshes everything the sale
  /// affects. Two reasons this is separate from printing:
  ///   • Saving and printing are different outcomes. A bill saved but not
  ///     printed (A4/A5 where the user dismisses the OS dialog, or a thermal
  ///     failure) previously showed NO confirmation at all, so the cashier
  ///     couldn't tell whether the sale was recorded.
  ///   • The billing screen is usually popped by [_navigateAfterBill] before a
  ///     PDF dialog closes, so a screen-local snackbar would never be seen.
  ///     [_showGlobalSnack] survives the pop.
  void _onBillSaved(Bill bill) {
    // Stock, history and (for a table order) the table's state all changed.
    _refreshAfterBill(bill);
    final label = bill.billNumber.isEmpty ? '' : bill.billNumber;
    _showGlobalSnack(context.l10n.billingBillSaved(label));
  }

  /// Refresh every view a finalized sale invalidates, so the app reflects the
  /// new state without a manual pull-to-refresh. Safe to call offline: each
  /// provider falls back to its local cache.
  void _refreshAfterBill(Bill bill) {
    // History gains the new bill.
    ref.read(billsProvider.notifier).refreshSilently();
    // Selling decrements stock — refresh the catalogue so quantities and
    // low-stock badges are current.
    ref.read(itemsProvider.notifier).refreshInBackground();
    // A credit (udhaari) sale changes what the customer owes.
    if (bill.paymentMode == 'credit' || _settlePrevCredit) {
      ref.read(creditCustomersProvider.notifier).refreshSilently();
    }
  }

  void _navigateAfterBill() {
    if (!mounted) return;
    if (widget.onBillDone != null) {
      widget.onBillDone!();
    } else if (Navigator.canPop(context)) {
      // Pushed for a specific table or an Open Orders draft — return to it.
      // The root Billing tab (nothing to pop) just stays put with a clean cart.
      Navigator.pop(context);
    }
  }

  Future<void> _generateBillOnline(List<CartEntry> cart,
      {void Function(Bill)? onBillReady}) async {
    final l10n = context.l10n;
    setState(() => _generatingBill = true);
    try {
      Map<String, dynamic> result;
      final additionalCharges = _chargesPayload();
      if (widget.activeBillId != null) {
        // Push the cart together with the current discount and charges, so
        // anything changed after reopening the draft reaches the bill before
        // it is finalized (the finalize step itself recomputes nothing).
        await updateBillItems(
          widget.activeBillId!,
          _cartPayload,
          discountAmount:
              double.tryParse(_discountAmtController.text.trim()) ?? 0.0,
          additionalCharges: additionalCharges,
        );
        result = await finalizeBill(widget.activeBillId!);
      } else {
        final draft = await createBill({
          'items': _cartPayload,
          'table_id': widget.tableId,
          if (_customerNameController.text.trim().isNotEmpty)
            'customer_name': _customerNameController.text.trim(),
          if (_customerPhoneController.text.trim().isNotEmpty)
            'customer_phone': _customerPhoneController.text.trim(),
          'payment_mode': _paymentMode,
          'status': 'draft',
          if (_discountAmtController.text.trim().isNotEmpty)
            'discount_amount': double.tryParse(_discountAmtController.text.trim()) ?? 0.0,
          if (additionalCharges.isNotEmpty)
            'additional_charges': additionalCharges,
        });
        result = await finalizeBill(draft['id']);
      }
      final bill = Bill.fromJson(result);

      // If the cashier opted to clear this customer's previous credit, settle
      // those unpaid bills with the SAME payment mode as this bill. The current
      // bill itself is separate. Best-effort: a settle failure is surfaced but
      // doesn't undo the finalized sale.
      if (_settlePrevCredit &&
          _prevCreditBillIds.isNotEmpty &&
          _paymentMode != 'credit') {
        final idsToSettle = List<String>.from(_prevCreditBillIds);
        final settleMode = _paymentMode;
        try {
          final res = await settleCreditBills(idsToSettle, settleMode);
          // Keep the settled bills so the print/WhatsApp action can handle each
          // on its own (bills are never merged). Stamp the settled mode so a
          // printed receipt shows how it was collected, not "Credit".
          _justSettledPrevBills = (res['bills'] as List? ?? [])
              .map((j) {
                final b = Bill.fromJson(j as Map<String, dynamic>);
                return _copyBillWithMode(b, settleMode);
              })
              .toList();
          _prevCreditBillIds = const [];
          _prevCreditDue = 0;
          _settlePrevCredit = false;
          _prevCreditPhone = null;
        } catch (e) {
          if (mounted) {
            _showSnack(l10n.creditSettleFailed, isError: true);
          }
        }
      }

      // Cache the invoice prefix from the authoritative bill number (e.g. the
      // 'INV' in 'INV-0007'), so offline receipts reuse the same prefix.
      final dash = bill.billNumber.lastIndexOf('-');
      if (dash > 0) {
        unawaited(saveBillPrefix(bill.billNumber.substring(0, dash)));
      }
      if (!mounted) return;
      // Optimistically flip the table to 'billed' so the Tables screen reflects
      // the finalized order the instant we pop, before the reconcile fetch.
      if (widget.tableId != null) {
        ref.read(tablesProvider.notifier).applyFinalized(
              widget.tableId!,
              billId: widget.activeBillId ?? bill.id,
            );
      }
      ref.read(cartProvider.notifier).clear();
      _customerNameController.clear();
      _customerPhoneController.clear();
      _discountPctController.clear();
      _discountAmtController.clear();
      _clearCharges();
      setState(() => _paymentMode = 'cash');
      ref.invalidate(reportProvider);
      ref.invalidate(billsProvider);
      // Reconcile table state with the server after the finalize commits.
      unawaited(ref.read(tablesProvider.notifier).refreshSilently());
      // A just-finalized table-less draft leaves the Open Orders queue — refresh
      // it so the completed order drops off the list.
      if (widget.tableId == null) {
        unawaited(ref.read(openDraftsProvider.notifier).refreshSilently());
      }
      // A finalized order is no longer a draft, so it leaves the kitchen queue —
      // ping so the Kitchen screen drops it immediately.
      NotificationService.instance.pingKitchen();
      // Confirm the save and refresh stock/history/credit BEFORE printing, so
      // the cashier sees it even when the print is dismissed or fails.
      _onBillSaved(bill);
      if (onBillReady != null) {
        onBillReady(bill);
      } else {
        _navigateAfterBill();
      }
    } on NetworkException {
      // Let the caller fall back to offline billing — don't show an error here.
      rethrow;
    } on ApiException catch (e) {
      // 5xx = server broke (its DB is down, etc.). Let the caller fall back to
      // offline billing so the sale isn't lost — don't show a generic error.
      if (e.statusCode >= 500) rethrow;
      if (e.statusCode == 409 && e.items != null && e.items!.isNotEmpty) {
        _showInsufficientStockDialog(e.items!);
      } else {
        _showSnack(e.serverMessage ?? e.message, isError: true);
      }
    } catch (_) {
      _showSnack(l10n.billingGenerateFailed, isError: true);
    } finally {
      if (mounted) setState(() => _generatingBill = false);
    }
  }

  void _showInsufficientStockDialog(List<Map<String, dynamic>> items) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.inventory_2_outlined,
                color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.billingInsufficientStock,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          // The out-of-stock list is unbounded; scroll rather than overflow
          // when many items (or longer Marathi labels) exceed the dialog.
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.billingInsufficientStockBody,
              style: AppFont.style(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final name = (item['item_name'] ?? item['name']) as String? ??
                  l10n.billingUnknownItem;
              final available = item['available'];
              final requested = item['requested'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child:
                          Icon(Icons.circle, size: 6, color: AppColors.error),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (available != null)
                      Flexible(
                        child: Text(
                          requested != null
                              ? l10n.billingStockAvailableAsked(
                                  '$available', '$requested')
                              : l10n.billingStockAvailable('$available'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.style(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> _generateBillOffline(List<CartEntry> cart,
      {void Function(Bill)? onBillReady}) async {
    final l10n = context.l10n;
    setState(() => _generatingBill = true);
    try {
      final businessId = await getBusinessId() ?? '';
      final userId = await getUserId() ?? '';
      // Offline bills get an 'INV-<deviceTag>-####' number: a per-device tag +
      // 4-digit counter, globally unique across devices. This number is printed
      // and given to the customer, so it is kept UNCHANGED when the bill syncs.
      final offlineBillNumber = await nextOfflineBillNumber();

      // GST off → tax is ignored entirely, even if an item still carries a
      // leftover tax_rate from when GST was on. Matches the cart providers, the
      // online path and the backend, so the printed Grand Total equals the Net
      // Payable shown on the order card.
      final gstEnabled = ref.read(gstEnabledProvider);

      double subtotal = 0;
      double taxAmount = 0;
      final lineItems = cart.map((e) {
        // lineNet/lineTax back out the tax from an MRP (tax-inclusive) price,
        // so unit_price sent to the server is always the NET rate — matching
        // resolveNetPriceAndRate in routes/bills.js and keeping an offline bill
        // identical to the one the server would have computed.
        final lineSub = e.lineNet(gstEnabled);
        final taxRate = gstEnabled ? e.item.taxRate : null;
        final lineTax = e.lineTax(gstEnabled);
        subtotal += lineSub;
        taxAmount += lineTax;
        return {
          'item_id': e.item.id,
          'variant_id': e.variant?.id,
          'item_name': e.displayName,
          'quantity': e.quantity,
          'unit_price': e.netPrice(gstEnabled),
          'tax_rate': taxRate,
          'line_total':
              double.parse((lineSub + lineTax).toStringAsFixed(2)),
        };
      }).toList();
      // Discount applies to the NET subtotal; tax is charged on the discounted
      // net. Clamp to subtotal and scale the tax so stored/printed/synced figures
      // all agree (bill-level: tax × discountedNet / net).
      final discountAmt = (double.tryParse(_discountAmtController.text) ?? 0.0)
          .clamp(0.0, subtotal);
      if (subtotal > 0) {
        taxAmount = double.parse(
            (taxAmount * (subtotal - discountAmt) / subtotal).toStringAsFixed(2));
      }
      // Additional charges sit on top of the taxed items: in the total, but
      // outside the tax base and untouched by the discount (same as the server).
      final charges = _chargeEntries();
      final chargesTotal = BillCharge.sum(charges);
      final total = double.parse(
          (subtotal + taxAmount + chargesTotal).toStringAsFixed(2));
      // Round-off is computed on-device and kept UNCHANGED when the bill syncs
      // (it's already printed on the customer's receipt), same as bill_number.
      final roundOff = computeRoundOff(
          total - discountAmt, ref.read(roundOffEnabledProvider));

      final queued = await OfflineService.instance.queueOfflineBill({
        'business_id': businessId,
        'user_id': userId,
        'table_id': widget.tableId,
        'bill_number': offlineBillNumber,
        'customer_name': _customerNameController.text.trim().nullIfEmpty,
        'customer_phone': _customerPhoneController.text.trim().nullIfEmpty,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmt,
        'charges_amount': chargesTotal,
        'additional_charges':
            charges.isEmpty ? null : BillCharge.encode(charges),
        'total': total,
        'round_off': roundOff,
        'payment_mode': _paymentMode,
        'items_json': jsonEncode(lineItems),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final localId = queued.localId;

      final fakeBill = Bill(
        id: localId,
        businessId: businessId,
        billNumber: offlineBillNumber,
        tableId: widget.tableId,
        tableNumber: widget.tableNumber,
        customerName: _customerNameController.text.trim().nullIfEmpty,
        customerPhone: _customerPhoneController.text.trim().nullIfEmpty,
        subtotal: subtotal,
        taxAmount: taxAmount,
        discountAmount: discountAmt,
        chargesAmount: chargesTotal,
        additionalCharges: charges,
        total: total,
        roundOff: roundOff,
        paymentMode: _paymentMode,
        status: 'finalized',
        createdByUserId: userId,
        createdAt: DateTime.now(),
        items: lineItems
            .map((li) => BillItem(
                  id: li['item_id'] as String,
                  billId: localId,
                  itemId: li['item_id'] as String,
                  variantId: li['variant_id'] as String?,
                  itemName: li['item_name'] as String,
                  quantity: (li['quantity'] as double),
                  unitPrice: (li['unit_price'] as double),
                  taxRate: li['tax_rate'] as double?,
                  lineTotal: (li['line_total'] as double),
                ))
            .toList(),
      );

      ref.read(cartProvider.notifier).clear();
      _customerNameController.clear();
      _customerPhoneController.clear();
      _discountPctController.clear();
      _discountAmtController.clear();
      _clearCharges();
      setState(() => _paymentMode = 'cash');
      // Deduct the sold quantities from the LOCAL item cache. The server does
      // this on sync, but until then the cached stock is the only figure the
      // app has — without this an offline sale leaves stock unchanged, so the
      // catalogue and low-stock badges stay wrong for the whole outage.
      await OfflineService.instance.applyStockDelta(businessId, lineItems);
      if (!mounted) return;
      // Same save confirmation + refresh as the online path.
      _onBillSaved(fakeBill);
      if (onBillReady != null) {
        onBillReady(fakeBill);
      } else {
        _navigateAfterBill();
      }
    } catch (e) {
      _showSnack(l10n.billingSavedOffline('$e'), isError: true);
    } finally {
      if (mounted) setState(() => _generatingBill = false);
    }
  }

  /// Copy of [bill] with [mode] as its payment mode, so a settled credit bill's
  /// printed receipt shows how it was collected instead of "Credit". Nothing is
  /// merged — this is one bill.
  Bill _copyBillWithMode(Bill bill, String mode) => Bill(
        id: bill.id,
        businessId: bill.businessId,
        billNumber: bill.billNumber,
        tableId: bill.tableId,
        tableNumber: bill.tableNumber,
        customerName: bill.customerName,
        customerPhone: bill.customerPhone,
        subtotal: bill.subtotal,
        taxAmount: bill.taxAmount,
        discountAmount: bill.discountAmount,
        total: bill.total,
        paymentMode: mode,
        status: bill.status,
        paymentStatus: 'paid',
        createdByUserId: bill.createdByUserId,
        createdAt: bill.createdAt,
        items: bill.items,
      );

  /// Build an in-memory [Bill] from the current cart + customer fields for
  /// preview/printing, WITHOUT queuing or saving it. Mirrors the totals and
  /// line-item math used by the real (offline) billing path.
  Bill _buildBillFromCart(List<CartEntry> cart) {
    double subtotal = 0;
    double taxAmount = 0;
    // GST off → tax ignored entirely, and an MRP price stops being split. Same
    // rule as the real billing paths so the preview matches the printed bill.
    final gstEnabled = ref.read(gstEnabledProvider);
    final items = cart.map((e) {
      final lineSub = e.lineNet(gstEnabled);
      final lineTax = e.lineTax(gstEnabled);
      subtotal += lineSub;
      taxAmount += lineTax;
      return BillItem(
        id: e.item.id,
        billId: 'preview',
        itemId: e.item.id,
        variantId: e.variant?.id,
        itemName: e.displayName,
        quantity: e.quantity,
        unitPrice: e.netPrice(gstEnabled),
        taxRate: gstEnabled ? e.item.taxRate : null,
        lineTotal: double.parse((lineSub + lineTax).toStringAsFixed(2)),
      );
    }).toList();
    // Discount on NET subtotal; tax charged on the discounted net (bill-level:
    // tax × discountedNet / net) so the preview/receipt matches the real bill.
    final discountAmt =
        (double.tryParse(_discountAmtController.text) ?? 0.0)
            .clamp(0.0, subtotal);
    if (subtotal > 0) {
      taxAmount = double.parse(
          (taxAmount * (subtotal - discountAmt) / subtotal).toStringAsFixed(2));
    }
    // Additional charges are in the total, untaxed and undiscounted.
    final charges = _chargeEntries();
    final chargesTotal = BillCharge.sum(charges);
    final total = double.parse(
        (subtotal + taxAmount + chargesTotal).toStringAsFixed(2));
    return Bill(
      id: 'preview',
      businessId: '',
      // A placeholder number for the preview; the real bill gets its number when
      // finalized (online) or from nextOfflineBillNumber() (offline).
      billNumber: widget.activeBillId ?? 'PREVIEW',
      tableId: widget.tableId,
      tableNumber: widget.tableNumber,
      customerName: _customerNameController.text.trim().nullIfEmpty,
      customerPhone: _customerPhoneController.text.trim().nullIfEmpty,
      subtotal: subtotal,
      taxAmount: taxAmount,
      discountAmount: discountAmt,
      chargesAmount: chargesTotal,
      additionalCharges: charges,
      total: total,
      roundOff: computeRoundOff(
          total - discountAmt, ref.read(roundOffEnabledProvider)),
      paymentMode: _paymentMode,
      status: 'preview',
      createdByUserId: '',
      createdAt: DateTime.now(),
      items: items,
    );
  }

  /// Show a real, WYSIWYG preview of the current cart as it would be printed —
  /// a thermal receipt bitmap (58/80mm) or an A5/A4 PDF, per the chosen paper
  /// size. Read-only: nothing is saved.
  Future<void> _previewBill() async {
    final l10n = context.l10n;
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack(l10n.billingAddAtLeastOneItem, isError: true);
      return;
    }
    final bill = _buildBillFromCart(cart);
    final businessName = ref.read(businessNameProvider);
    final labels = ReceiptLabels.from(l10n, ref.read(localeProvider).code);
    final profile = await getGstProfile();
    final addr = profile['business_address'] ?? '';
    final phone = profile['business_phone'] ?? '';
    final fss = profile['fssai_number'] ?? '';
    final sac = profile['default_sac_code'] ?? '';
    final gstEnabled = ref.read(gstEnabledProvider);
    String? gstin;
    if (gstEnabled) {
      final g = profile['gst_number'] ?? '';
      gstin = g.isNotEmpty ? g : null;
    }

    ReceiptPreview preview;
    try {
      preview = await ReceiptOutput.buildPreview(
        bill,
        businessName: businessName,
        businessAddress: addr.isNotEmpty ? addr : null,
        businessPhone: phone.isNotEmpty ? phone : null,
        businessGstin: gstin,
        businessFssai: fss.isNotEmpty ? fss : null,
        defaultSacCode: sac.isNotEmpty ? sac : null,
        gstEnabled: gstEnabled,
        labels: labels,
      );
    } catch (e) {
      if (mounted) _showSnack(l10n.billingPrintFailed('$e'), isError: true);
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillPreviewScreen(preview: preview),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _autoPrint(Bill bill) async {
    final l10n = context.l10n;
    final businessName = ref.read(businessNameProvider);
    final labels = ReceiptLabels.from(l10n, ref.read(localeProvider).code);
    // Address, phone and FSSAI print whenever available, regardless of GST.
    // GSTIN remains gated on GST being enabled (gstin stays null when off, so a
    // non-GST receipt is byte-for-byte as before).
    final profile = await getGstProfile();
    final addr = profile['business_address'] ?? '';
    final ph = profile['business_phone'] ?? '';
    final fss = profile['fssai_number'] ?? '';
    final String? address = addr.isNotEmpty ? addr : null;
    final String? phone = ph.isNotEmpty ? ph : null;
    final String? fssai = fss.isNotEmpty ? fss : null;
    final sac = profile['default_sac_code'] ?? '';
    final gstEnabled = ref.read(gstEnabledProvider);
    String? gstin;
    if (gstEnabled) {
      final g = profile['gst_number'] ?? '';
      gstin = g.isNotEmpty ? g : null;
    }
    // Consume any previous credit bills that were settled with this bill —
    // each prints as its OWN receipt (never merged), one tap prints them all.
    // ReceiptOutput routes to thermal (printBills) or an A5/A4 PDF per the
    // chosen paper size; thermal settles the BT link between jobs.
    final prevBills = _justSettledPrevBills;
    _justSettledPrevBills = const [];
    try {
      await ReceiptOutput.emit([bill, ...prevBills],
          businessName: businessName,
          businessAddress: address,
          businessPhone: phone,
          businessGstin: gstin,
          businessFssai: fssai,
          defaultSacCode: sac.isNotEmpty ? sac : null,
          gstEnabled: gstEnabled,
          labels: labels);
      if (mounted) _showSnack(l10n.billingPrintSuccess);
    } on PrinterException catch (e) {
      // The print just failed (BT off, out of range, unpaired…): re-check
      // reachability so the finalize button reflects it (Print → Save).
      ref.invalidate(canPrintProvider);
      // 'No printer configured' is an internal sentinel, not a user string.
      if (e.message == 'No printer configured') return;
      if (mounted) _showSnack(l10n.billingPrintFailed(e.message), isError: true);
    } catch (e) {
      ref.invalidate(canPrintProvider);
      if (mounted) _showSnack(l10n.billingPrintFailed('$e'), isError: true);
    }
  }

  Future<void> _sendBillWhatsApp(Bill bill) async {
    final l10n = context.l10n;
    // Also handle each settled previous credit bill's receipt separately.
    final prevBills = _justSettledPrevBills;
    _justSettledPrevBills = const [];
    try {
      // --- API-template send (WhatsApp Business API) — disabled for now ---
      // await sendBillWhatsApp(bill.id);
      // for (final b in prevBills) {
      //   await sendBillWhatsApp(b.id);
      // }

      // Deep-link send: open the user's own WhatsApp with a prefilled message
      // to the customer's number. The cashier taps Send. Opening several chats
      // at once isn't possible, so we open the current bill; any settled
      // previous bills open in sequence after a short gap.
      await _openWhatsAppForBill(bill.id);
      for (final b in prevBills) {
        await Future.delayed(const Duration(milliseconds: 300));
        await _openWhatsAppForBill(b.id);
      }
    } on ApiException catch (e) {
      if (mounted) {
        _showSnack(l10n.billingWhatsappFailedWithError(e.message),
            isError: true);
      }
    } catch (_) {
      if (mounted) _showSnack(l10n.billingWhatsappFailed, isError: true);
    }
  }

  /// Delivers the bill's receipt over WhatsApp. The backend decides by the
  /// business's mode: 'api' (paid) sends the template server-side — we just
  /// confirm; 'deeplink' (free) returns phone + message and we open the
  /// cashier's WhatsApp (whatsapp:// first, then wa.me).
  Future<void> _openWhatsAppForBill(String billId) async {
    final data = await whatsAppBill(billId);

    // Paid API mode: backend already sent it. Nothing to open.
    if (data['mode'] == 'api') {
      if (data['sent'] == true) {
        if (mounted) _showSnack(context.l10n.billingWhatsappSent);
      } else if (mounted) {
        _showSnack(
          (data['error'] ?? context.l10n.billingWhatsappFailed).toString(),
          isError: true,
        );
      }
      return;
    }

    // Free deeplink mode: open the cashier's WhatsApp with the prefilled text.
    final phone = (data['phone'] ?? '').toString();
    final message = (data['message'] ?? '').toString();
    if (phone.isEmpty) {
      if (mounted) _showSnack(context.l10n.billingWhatsappFailed, isError: true);
      return;
    }
    final text = Uri.encodeComponent(message);
    final candidates = [
      Uri.parse('whatsapp://send?phone=$phone&text=$text'),
      Uri.parse('https://wa.me/$phone?text=$text'),
      Uri.parse('https://api.whatsapp.com/send?phone=$phone&text=$text'),
    ];
    Object? lastError;
    for (final uri in candidates) {
      try {
        final ok =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return; // opened successfully
      } catch (e) {
        lastError = e; // try the next candidate
      }
    }
    // Every strategy failed — surface the real reason so we can diagnose.
    if (mounted) {
      _showSnack(
        lastError != null
            ? 'WhatsApp could not open: $lastError'
            : context.l10n.billingWhatsappFailed,
        isError: true,
      );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor:
          isError ? AppColors.error : const Color(0xFF0F172A),
    ));
  }

  /// Like [_showSnack] but routed through the app-wide messenger, so it still
  /// appears when this screen has already been popped (background save reconcile).
  void _showGlobalSnack(String message, {bool isError = false}) {
    rootMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: isError ? AppColors.error : const Color(0xFF0F172A),
    ));
  }

  // ignore: unused_element
  Future<void> _logout() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.error,
                  size: 26,
                ),
              ),
              const SizedBox(height: AppSpacing.space16),
              Text(
                l10n.logoutConfirmTitle,
                style: Theme.of(ctx).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space8),
              Text(
                l10n.logoutConfirmBody,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                      child: Text(l10n.commonCancel,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        minimumSize: const Size(0, 46),
                      ),
                      child: Text(l10n.logout,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final businessName = ref.watch(businessNameProvider);
    final userName = ref.watch(userNameProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildAppBar(businessName, userName),
          Expanded(child: isWide ? _buildWideLayout() : _buildNarrowLayout()),
        ],
      ),
    );
  }

  ShellAppBar _buildAppBar(String businessName, String userName) {
    final l10n = context.l10n;
    // Show a back arrow only when this screen was pushed — opened from a table
    // (tableId) or from Open Orders (activeBillId) — not when it's the root
    // Billing tab, where an open cart/variant sheet would otherwise flip
    // Navigator.canPop() and reveal a stray arrow.
    final isPushed = widget.tableId != null ||
        widget.activeBillId != null ||
        widget.onBillDone != null;
    return ShellAppBar(
      automaticallyImplyLeading: isPushed,
      title: AnimatedOpacity(
        opacity: _searchExpanded ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(businessName,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (widget.tableNumber != null)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.billingTableNumber(widget.tableNumber!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _searchAnim,
              builder: (context, child) {
                final maxWidth = MediaQuery.of(context).size.width - 80;
                return SizedBox(
                  width: _searchAnim.value * maxWidth,
                  // Fixed height keeps the expanded field within the toolbar so
                  // it can't overflow the app bar vertically.
                  height: 40,
                  child: Opacity(
                    opacity: _searchAnim.value,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: l10n.billingSearchItems,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _searchExpanded
                    ? const Icon(Icons.close, key: ValueKey('close'), size: 20)
                    : const Icon(Icons.search, key: ValueKey('search'), size: 20),
              ),
              color: AppColors.textSecondary,
              onPressed: () {
                setState(() => _searchExpanded = !_searchExpanded);
                if (_searchExpanded) {
                  _searchAnimCtrl.forward();
                  Future.delayed(const Duration(milliseconds: 250), () {
                    if (mounted) _searchFocus.requestFocus();
                  });
                } else {
                  _searchAnimCtrl.reverse();
                  _searchController.clear();
                  _searchFocus.unfocus();
                }
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: _buildItemsPanel()),
        Container(width: 1, color: AppColors.border),
        SizedBox(width: 360, child: _buildCartPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Consumer(builder: (context, ref, _) {
      final l10n = context.l10n;
      final count = ref.watch(cartItemCountProvider);
      return Stack(
        children: [
          _buildItemsPanel(),
          // Park-order + Cart row. Shown whenever the cart has items — for
          // tables it saves a table draft; on the standalone billing page it
          // saves a table-less "open order" everyone can create.
          if (count > 0)
            Positioned(
              bottom: AppSpacing.space16,
              left: AppSpacing.space16,
              right: AppSpacing.space16,
              child: Row(
                children: [
                  Expanded(
                    child: FloatingActionButton.extended(
                      heroTag: 'saveDraftFab',
                      onPressed: (count == 0 || _savingDraft) ? null : _saveDraft,
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.primary,
                      elevation: 4,
                      icon: _savingDraft
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 20),
                      label: Text(
                        _savingDraft ? l10n.commonSaving : _parkLabel(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Expanded(
                    child: FloatingActionButton.extended(
                      heroTag: 'cartFab',
                      onPressed: _openCartSheet,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                      label: Text(
                        count == 0 ? l10n.billingCart : l10n.billingCartWithCount(count),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  // Size picker — shown when a variant item is tapped or swiped. Each size has
  // its own − / + stepper and stays open so multiple sizes and quantities can
  // be set in one go. Each size is a separate cart line (independent stock).
  void _showVariantPicker(Item item) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      // Let the sheet grow and — crucially — sit above the keyboard, so the
      // editable quantity field on each size row stays visible while typing.
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) {
        // Watch the cart so per-size quantities update live. Each size is
        // rendered with the SAME _ExcelItemRow used on the billing page, so it
        // gets the identical − / + stepper and left/right swipe gestures.
        return Consumer(builder: (context, ref, _) {
          final cart = ref.watch(cartProvider);
          final notifier = ref.read(cartProvider.notifier);
          double qtyOf(ItemVariant v) => cart
              .where((e) => e.key == '${item.id}:${v.id}')
              .fold(0.0, (s, e) => s + e.quantity);

          // Pad the sheet up by the keyboard height so its content (including
          // the editable quantity field) is never hidden behind the keyboard.
          final keyboardHeight = MediaQuery.of(sheetCtx).viewInsets.bottom;
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            duration: const Duration(milliseconds: 200),
            curve: Curves.decelerate,
            child: SafeArea(
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    l10n.billingChooseSize(item.name),
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 1),
                for (int idx = 0; idx < item.variants.length; idx++) ...[
                  if (idx > 0)
                    const Divider(height: 1, indent: 12, endIndent: 12),
                  Builder(builder: (_) {
                    final v = item.variants[idx];
                    final key = '${item.id}:${v.id}';
                    return _ExcelItemRow(
                      index: idx + 1,
                      item: item,
                      variant: v,
                      qty: qtyOf(v),
                      onAdd: () => notifier.addItem(item, variant: v),
                      onIncrement: () => notifier.addItem(item, variant: v),
                      onDecrement: () => notifier.changeQty(key, -1),
                      onSetQty: (q) => notifier.setQty(key, q),
                    );
                  }),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: PrimaryButton(
                    text: l10n.commonDone,
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ),
              ],
            ),
            ),
            ),
          );
        });
      },
    );
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) {
        final keyboardHeight = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // Expose the sheet's setter so credit-error changes (driven from
            // button handlers) can rebuild the sheet, not just the parent.
            _sheetSetState = setSheet;
            return AnimatedPadding(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              duration: const Duration(milliseconds: 200),
              curve: Curves.decelerate,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
                ),
                child: SingleChildScrollView(
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  child: _buildCartPanel(inSheet: true),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => _sheetSetState = null);
  }

  // ---------------------------------------------------------------------------
  // Items panel
  // ---------------------------------------------------------------------------

  Widget _buildItemsPanel() {
    return _buildItemList();
  }

  Widget _buildItemList() {
    return Consumer(builder: (context, ref, _) {
      final itemsAsync = ref.watch(itemsProvider);
      final cart = ref.watch(cartProvider);
      final cats = ref.watch(categoriesProvider).valueOrNull ?? [];

      // Search + category header slivers — always scrollable.
      // (Stale-cache banner removed: items auto-refresh on app open instead.)
      List<Widget> headerSlivers() => [
        if (cats.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                primary: false,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space12),
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.space8),
                itemBuilder: (_, i) {
                  final cat = cats[i];
                  final selected = _selectedCategory == cat;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: FilterChip(
                      label: Text(cat),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _selectedCategory = _selectedCategory == cat ? '' : cat;
                      }),
                      backgroundColor: AppColors.surfaceVariant,
                      selectedColor: AppColors.primaryLight,
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
                    ),
                  );
                },
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
      ];

      return itemsAsync.when(
        loading: () => const BillingSkeleton(),
        error: (e, _) => NoInternetWidget(onRetry: () => ref.invalidate(itemsProvider)),
        data: (allItems) {
          if (allItems.isEmpty && !ref.read(connectivityProvider)) {
            return NoInternetWidget(onRetry: () => ref.invalidate(itemsProvider));
          }
          final items = _filteredItems(allItems);
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(itemsProvider);
                ref.invalidate(categoriesProvider);
                await ref.read(itemsProvider.future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  ...headerSlivers(),
                  SliverFillRemaining(
                    child: EmptyState(
                        icon: Icons.search_off_outlined,
                        message: context.l10n.billingNoItemsFound),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(itemsProvider);
              ref.invalidate(categoriesProvider);
              await ref.read(itemsProvider.future);
            },
            child: _ExcelItemTable(
              items: items,
              cart: cart,
              headerSlivers: headerSlivers(),
              // Variant items can't map a single stepper to one of several
              // sizes, so every qty action (+/-/set) opens the size picker.
              onAdd: (item) {
                if (item.hasVariants) {
                  _showVariantPicker(item);
                } else {
                  ref.read(cartProvider.notifier).addItem(item);
                }
              },
              onDecrement: (item) {
                if (item.hasVariants) {
                  _showVariantPicker(item);
                } else {
                  ref
                      .read(cartProvider.notifier)
                      .changeQty(CartNotifier.keyFor(item.id), -1);
                }
              },
              onIncrement: (item) {
                if (item.hasVariants) {
                  _showVariantPicker(item);
                } else {
                  ref
                      .read(cartProvider.notifier)
                      .changeQty(CartNotifier.keyFor(item.id), 1);
                }
              },
              onSetQty: (item, qty) {
                if (item.hasVariants) {
                  _showVariantPicker(item);
                } else {
                  ref
                      .read(cartProvider.notifier)
                      .setQty(CartNotifier.keyFor(item.id), qty);
                }
              },
            ),
          );
        },
      );
    });
  }

 
  // ---------------------------------------------------------------------------
  // Cart panel
  // ---------------------------------------------------------------------------

  /// Empty-cart placeholder — a compact icon + message. Kept intrinsic (not
  /// Expanded) so the footer actions follow directly beneath it rather than
  /// being pushed to the bottom of a tall panel.
  Widget _emptyCartPlaceholder(AppLocalizations l10n) {
    // Centred and scrollable: in the wide layout this sits in an Expanded whose
    // height is whatever the pinned footer leaves over. On a short window that
    // can be less than the icon + text need, which overflowed the column — so
    // let it scroll rather than paint past its bounds.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.space24, horizontal: AppSpacing.space16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: const Icon(Icons.shopping_cart_outlined,
                  size: 28, color: AppColors.textDisabled),
            ),
            const SizedBox(height: AppSpacing.space12),
            Text(l10n.billingNoItemsAddedYet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// Build the CGST/SGST rows for the cart totals when GST is enabled.
  /// Each is half the [tax]; the rate is derived from the taxable [subtotal]
  /// (e.g. 18% GST → CGST 9% / SGST 9%). Returns (label, amount) pairs.
  List<(String, String)> _gstSplitRows(
      AppLocalizations l10n, double subtotal, double tax) {
    // Split in paise and give the odd one to CGST, so CGST + SGST always adds
    // back to exactly [tax]. Printing (tax / 2) twice loses or gains a paisa on
    // any odd-paise tax (0.95 -> 0.47 + 0.47 = 0.94), which would make this card
    // disagree with the printed receipt by 0.01. Mirrors _gstHalves() in
    // printer_service_native.dart.
    final paise = (tax * 100).round();
    final cgstAmt = ((paise + 1) ~/ 2) / 100;
    final sgstAmt = (paise ~/ 2) / 100;
    // Effective half-rate for the label; blank-safe when subtotal is 0.
    String rate = '';
    if (subtotal > 0) {
      final r = tax / subtotal * 100 / 2;
      rate = r % 1 == 0 ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
    }
    return [
      (l10n.billingCgst(rate), cgstAmt.toStringAsFixed(2)),
      (l10n.billingSgst(rate), sgstAmt.toStringAsFixed(2)),
    ];
  }

  Widget _buildCartPanel({bool inSheet = false}) {
    return Consumer(builder: (context, ref, _) {
      final l10n = context.l10n;
      final cart = ref.watch(cartProvider);
      final subtotal = ref.watch(cartSubtotalProvider);
      final tax = ref.watch(cartTaxProvider);
      // When GST is enabled, the tax is shown split as CGST + SGST (each half)
      // in the totals summary below, mirroring the printed receipt.
      final gstEnabled = ref.watch(gstEnabledProvider);
      // A server takes/builds orders and sends them to the kitchen but cannot
      // finalize or take payment — hide the finalize (WhatsApp/Print) actions.
      final canFinalize = ref.watch(userRoleProvider) != 'server';
      // Printer reachability no longer changes any label here — it only picks
      // which finish the default settle runs, read at that moment in _settle.
      // Still watched so the settle menu's print row reflects a printer that
      // connects or drops while the cart is open.
      ref.watch(printReadyProvider);

      return Container(
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: inSheet ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (inSheet)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            // Header — always visible. Same 16px gutter as the payment mode,
            // customer and discount fields below, so the trailing icons line up
            // with the right edge of those inputs rather than floating past it.
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space16, AppSpacing.space16, AppSpacing.space8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: const Icon(Icons.shopping_cart_outlined,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  // Title + count share ONE Expanded, which absorbs all the
                  // free width. A Spacer here instead would get nothing —
                  // Flexible and Spacer compete for the same slack, and the
                  // Flexible wins, which left the trailing icons stranded in
                  // the middle of the row instead of at its edge.
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(l10n.billingOrder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                        // Item count beside the title — distinct LINES, not
                        // summed quantity, so a 1.5 kg line still reads as one
                        // item (matches the cart badge). Hidden on an empty
                        // cart: the placeholder below already says so.
                        if (cart.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.space8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.large),
                            ),
                            child: Text(
                              l10n.billingOrderItemCount(cart.length),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Preview lives up here with the other order-level actions
                  // because it is the one control that touches no money — it
                  // must not sit in the footer row where everything settles.
                  if (cart.isNotEmpty)
                    _HeaderIconAction(
                      icon: Icons.visibility_outlined,
                      color: AppColors.primary,
                      tooltip: l10n.billingPreviewReceipt,
                      onPressed: _savingDraft ? null : _previewBill,
                    ),
                  // Clearing a cart / releasing a table is a cashier/owner
                  // action — hidden for servers, who only build orders.
                  //
                  // The word is dropped: a red bin next to a blue eye reads
                  // faster than a labelled button, and the label was the only
                  // thing making this header row crowd on a narrow phone. The
                  // tooltip and the confirm dialog carry the meaning.
                  if (cart.isNotEmpty && canFinalize) ...[
                    const SizedBox(width: 6),
                    _HeaderIconAction(
                      icon: Icons.delete_outline,
                      color: AppColors.error,
                      tooltip: l10n.commonClear,
                      onPressed: () => _clearCart(inSheet: inSheet),
                    ),
                  ],
                ],
              ),
            ),

            // Scrollable cart items — takes all available space
            if (cart.isEmpty)
              // Empty cart: a compact icon + message. In the wide layout it
              // takes the leftover space via Expanded so the pinned footer sits
              // at the BOTTOM of the panel, in the same place it occupies once
              // items are added — the controls must not jump as the first item
              // goes in.
              //
              // Center is load-bearing, not decoration: Expanded forces a tight
              // height on its child, and the placeholder's own height is fixed,
              // so on a short window it painted past the bounds (the yellow
              // "BOTTOM OVERFLOWED" stripe). Center relaxes that to a loose
              // constraint and the scroll view inside absorbs the rest.
              //
              // The sheet is min-sized and scrolls as a whole, so no Expanded.
              (inSheet
                  ? _emptyCartPlaceholder(l10n)
                  : Expanded(
                      child: Center(child: _emptyCartPlaceholder(l10n))))
            else if (inSheet)
              // In bottom sheet: not constrained, just list
              Column(
                mainAxisSize: MainAxisSize.min,
                children: cart.map((e) => _buildCartRow(e)).toList(),
              )
            else
              // In wide layout: scrollable list that takes remaining space.
              // This is the ONLY scrollable region of the panel.
              Expanded(
                child: ListView(
                  children: cart.map((e) => _buildCartRow(e)).toList(),
                ),
              ),

            // Footer (payment, customer, discount, totals, actions) — pinned to
            // the bottom and never scrolls; see [_wrapFooter].
            _wrapFooter(
              [
            const Divider(height: 1),

            // Payment mode — placed before customer details so the payment
            // choice is made first (and, for Credit, prompts for the now-visible
            // name/phone below). Hidden for servers; taking payment is a
            // cashier/owner step.
            if (canFinalize)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space16, AppSpacing.space16, 0),
              child: DropdownButtonFormField<String>(
                value: _paymentMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.billingPaymentMode,
                  prefixIcon: const Icon(Icons.payments_outlined,
                      size: 18, color: AppColors.textSecondary),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'cash',
                      child: Text(l10n.paymentCash,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: 'upi',
                      child: Text(l10n.paymentUpi,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: 'card',
                      child: Text(l10n.paymentCard,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: 'other',
                      child: Text(l10n.paymentOther,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  // Credit (udhaari): finalize the sale now, collect later.
                  // Requires customer name + phone (enforced at checkout).
                  DropdownMenuItem(
                      value: 'credit',
                      child: Text(l10n.paymentCredit,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _paymentMode = v!);
                  // Leaving credit clears any pending "name/phone required"
                  // message; the fields are only mandatory for credit.
                  if (_paymentMode != 'credit' && _creditError != null) {
                    _setCreditError(null);
                  } else {
                    _sheetSetState?.call(() {});
                  }
                },
              ),
            ),

            // Inline credit validation message — shown inside the card (no
            // snackbar, no closing) when a credit bill lacks name/phone.
            if (canFinalize && _creditError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                    AppSpacing.space8, AppSpacing.space16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.space8),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: AppSpacing.space8),
                      Expanded(
                        child: Text(
                          _creditError!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Customer info — local StatefulBuilder so toggle works in both
            // the wide layout and the bottom sheet independently
            StatefulBuilder(
              builder: (ctx, setLocal) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () =>
                        setLocal(() => _showCustomerFields = !_showCustomerFields),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space16, vertical: 10.0),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: AppSpacing.space8),
                          Expanded(
                            child: Text(
                              l10n.billingCustomerDetails,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: _showCustomerFields ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                                Icons.keyboard_arrow_down_outlined,
                                size: 18,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _showCustomerFields
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.space16,
                                0,
                                AppSpacing.space16,
                                AppSpacing.space12),
                            child: Column(
                              children: [
                                AppTextField(
                                  key: _customerNameKey,
                                  label: l10n.billingCustomerNameLabel,
                                  controller: _customerNameController,
                                  focusNode: _customerNameFocus,
                                  capitalizeWords: true,
                                  prefixIcon: const Icon(Icons.person_outline,
                                      size: 16,
                                      color: AppColors.textSecondary),
                                ),
                                _customerSuggestionList('name'),
                                const SizedBox(height: AppSpacing.space8),
                                AppTextField(
                                  key: _customerPhoneKey,
                                  label: l10n.billingCustomerPhoneLabel,
                                  controller: _customerPhoneController,
                                  focusNode: _customerPhoneFocus,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 10,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  prefixIcon: const Icon(Icons.phone_outlined,
                                      size: 16,
                                      color: AppColors.textSecondary),
                                ),
                                _customerSuggestionList('phone'),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // Previous credit due for this phone — shown below the customer
            // fields with a toggle to clear it together with the current bill.
            if (canFinalize && _prevCreditDue > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                    AppSpacing.space8, AppSpacing.space16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.space12,
                            AppSpacing.space8, AppSpacing.space12, 0),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined,
                                size: 16, color: AppColors.warning),
                            const SizedBox(width: AppSpacing.space8),
                            Expanded(
                              child: Text(
                                l10n.billingPrevCreditDue(
                                    _prevCreditDue.toStringAsFixed(2),
                                    _prevCreditBillIds.length),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space12),
                        value: _settlePrevCredit,
                        // Selected color comes from the theme's switchTheme; no
                        // per-widget override (the param name differs across
                        // Flutter versions — activeColor vs activeThumbColor).
                        title: Text(l10n.billingClearPrevCredit,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        onChanged: (v) {
                          setState(() => _settlePrevCredit = v);
                          _sheetSetState?.call(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),

            // Discount row — also cashier/owner only; servers don't apply
            // discounts when building an order.
            if (canFinalize)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                  AppSpacing.space12, AppSpacing.space16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      key: _discountPctKey,
                      label: l10n.billingDiscountPercent,
                      controller: _discountPctController,
                      focusNode: _discountPctFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      prefixIcon: const Icon(Icons.percent,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: AppTextField(
                      key: _discountAmtKey,
                      label: l10n.billingDiscountRupees,
                      controller: _discountAmtController,
                      focusNode: _discountAmtFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      prefixIcon: const Icon(Icons.currency_rupee,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // Additional charges — delivery, packaging, service, etc. Added on
            // top of the taxed items (no GST on them, never discounted). Same
            // cashier/owner gate as the discount above.
            if (canFinalize)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                    AppSpacing.space12, AppSpacing.space16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.billingAdditionalCharges,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              _charges.length >= _maxAdditionalCharges
                                  ? null
                                  : _addChargeRow,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(l10n.billingAddCharge),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space8),
                          ),
                        ),
                      ],
                    ),
                    if (_charges.isEmpty)
                      Text(
                        l10n.billingAdditionalChargesHint,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    for (final row in _charges)
                      Padding(
                        key: row.key,
                        padding:
                            const EdgeInsets.only(top: AppSpacing.space8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: AppTextField(
                                label: l10n.billingChargeDescription,
                                hint: l10n.billingChargeDescriptionHint,
                                controller: row.nameController,
                                focusNode: row.nameFocus,
                                capitalizeWords: true,
                                maxLength: 100,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.space8),
                            Expanded(
                              flex: 2,
                              child: AppTextField(
                                label: l10n.billingChargeAmount,
                                controller: row.amountController,
                                focusNode: row.amountFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                prefixIcon: const Icon(Icons.currency_rupee,
                                    size: 16, color: AppColors.textSecondary),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.billingRemoveCharge,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close,
                                  size: 18, color: AppColors.textSecondary),
                              onPressed: () => _removeChargeRow(row),
                            ),
                          ],
                        ),
                        // Past descriptions, under the focused field.
                        _chargeSuggestionList(row),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            // Bill summary
            if (cart.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                    AppSpacing.space12, AppSpacing.space16, 0),
                child: Builder(builder: (ctx) {
                  // Discount is applied to the NET (pre-tax) subtotal, then tax is
                  // charged on the discounted net. So the discount clamps to the
                  // subtotal, and the tax shown here is scaled down in proportion
                  // to the discount (bill-level: originalTax × discountedNet/net).
                  final discountAmt =
                      (double.tryParse(_discountAmtController.text) ?? 0.0)
                          .clamp(0.0, subtotal);
                  final discountedNet = subtotal - discountAmt;
                  final effectiveTax =
                      subtotal > 0 ? tax * discountedNet / subtotal : 0.0;
                  // "Total" here means subtotal + the (discounted) tax; the
                  // discount is broken out on its own row below, so payable is
                  // total − discount (+ round-off / prev due), which equals
                  // discountedNet + effectiveTax. The identity holds because the
                  // tax already reflects the discount.
                  // Additional charges ride on top of the taxed items — never
                  // taxed, never discounted — and are part of the total.
                  final charges = _chargeEntries();
                  final chargesTotal = BillCharge.sum(charges);
                  final total = subtotal + effectiveTax + chargesTotal;
                  // Invoice round-off applies to THIS bill's payable
                  // (total - discount), independent of any previous-due amount,
                  // matching the backend. 0 when the business has it disabled.
                  final roundOff = computeRoundOff(
                      total - discountAmt, ref.watch(roundOffEnabledProvider));
                  // When "clear previous credit" is on, the old due is added to
                  // this bill's payable, so the customer pays one combined
                  // amount and those old bills are settled on finalize.
                  final prevDue =
                      _settlePrevCredit ? _prevCreditDue : 0.0;
                  final netPayable = total - discountAmt + roundOff + prevDue;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Column(
                      children: [
                        // Sub Total row — pure item amount (no tax, no discount).
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.billingSubtotal,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.space8),
                              Text(
                                '₹${subtotal.toStringAsFixed(2)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                              ),
                            ],
                          ),
                        ),
                        // Discount row — only when applied. Shown right after the
                        // sub total (it reduces the taxable amount below).
                        if (discountAmt > 0) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.billingDiscountApplied,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.space8),
                                Text(
                                  '− ₹${discountAmt.toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF16A34A),
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // CGST / SGST split — shown ONLY when GST is enabled and
                        // the (discounted) cart carries tax. Each is half the tax;
                        // the rate is derived from the discounted taxable base
                        // (e.g. 18% → 9% + 9%). When GST is off, tax is ignored
                        // entirely, so this block never renders. Placed after the
                        // discount because tax is charged on the discounted net.
                        if (gstEnabled && effectiveTax > 0) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final line
                                    in _gstSplitRows(l10n, discountedNet, effectiveTax))
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            line.$1,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: AppSpacing.space8),
                                        Text(
                                          '₹${line.$2}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        // Additional charges — one row per charge, after tax
                        // since they are added on top of the taxed amount.
                        if (charges.isNotEmpty) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final c in charges)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: AppSpacing.space8),
                                        Text(
                                          '+ ₹${c.amount.toStringAsFixed(2)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        // Round Off row — only when a non-zero adjustment.
                        if (roundOff != 0) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.billingRoundOff,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.space8),
                                Text(
                                  '${roundOff < 0 ? '−' : '+'} ₹${roundOff.abs().toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Previous Due row — added to payable when the toggle
                        // above is on.
                        if (prevDue > 0) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.billingPreviousDue,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.space8),
                                Text(
                                  '+ ₹${prevDue.toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.warning,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Net Payable — highlighted footer
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.only(
                              bottomLeft:
                                  Radius.circular(AppRadius.small - 1),
                              bottomRight:
                                  Radius.circular(AppRadius.small - 1),
                              topLeft: (discountAmt > 0 || charges.isNotEmpty || roundOff != 0 || prevDue > 0)
                                  ? Radius.zero
                                  : Radius.circular(AppRadius.small - 1),
                              topRight: (discountAmt > 0 || charges.isNotEmpty || roundOff != 0 || prevDue > 0)
                                  ? Radius.zero
                                  : Radius.circular(AppRadius.small - 1),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space12, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.billingNetPayable,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(ctx).textTheme.bodyMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.space8),
                              Text(
                                '₹${netPayable.toStringAsFixed(2)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: Theme.of(ctx)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),

            // ONE action row: Hold · WhatsApp · Settle, then the printer's
            // state on the line below.
            //
            // Every action is visible — nothing hidden behind a dropdown the
            // cashier would have to open to learn what the main button does.
            // The two icons carry one-word captions because an icon alone
            // cannot say whether it takes the customer's money: WhatsApp
            // finalizes the bill exactly as settling does, so it is captioned
            // "Settle" and coloured as a money action, not as a share.
            //
            // A captain cannot settle, so only Hold renders and it takes the
            // whole row.
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.space16,
                AppSpacing.space12,
                AppSpacing.space16,
                AppSpacing.space16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (canFinalize) ...[
                        // Reversible, and the only control in the row that is.
                        IconAction(
                          icon: Icons.pause_circle_outline,
                          caption: l10n.billingHoldShort,
                          color: AppColors.warning,
                          tooltip: _parkLabel(l10n),
                          onPressed: (cart.isEmpty || _savingDraft)
                              ? null
                              : () => _park(inSheet: inSheet),
                        ),
                        const SizedBox(width: AppSpacing.space8),
                        IconAction(
                          // The real mark, so the destination is unmistakable —
                          // a generic speech bubble could be SMS or a note.
                          glyphBuilder: (size, color) =>
                              WhatsAppMark(size: size, color: color),
                          // Captioned for what it DOES, not for the app it
                          // opens — it settles first and shares second.
                          caption: l10n.billingWhatsappCaption,
                          color: whatsAppGreen,
                          tooltip: l10n.billingSettleWhatsapp,
                          onPressed: (cart.isEmpty || _generatingBill)
                              ? null
                              : () => _settleWhatsApp(inSheet: inSheet),
                        ),
                        const SizedBox(width: AppSpacing.space8),
                        Expanded(
                          child: SettleButton(
                            // The amount IS the label: the cashier reads the
                            // figure at the instant of committing to it.
                            amountLabel: l10n.billingSettleAmount(
                                '₹${_netPayable().toStringAsFixed(2)}'),
                            // ...and the second line says how it ends, so a
                            // printer that dropped is visible BEFORE the tap.
                            outcomeLabel: ref.watch(printReadyProvider)
                                ? l10n.billingSettleAndPrint
                                : l10n.billingSettleNoReceipt,
                            isLoading: _generatingBill,
                            longPressHint: l10n.billingSettleOnlyHint,
                            onPressed: (cart.isEmpty || _generatingBill)
                                ? null
                                : () => _settle(inSheet: inSheet),
                            // The deliberate skip, for when a printer is
                            // connected but this one sale needs no slip.
                            onLongPress: (cart.isEmpty || _generatingBill)
                                ? null
                                : () => _settle(inSheet: inSheet, withReceipt: false),
                          ),
                        ),
                      ] else
                        // Captain: parking is the only thing they can do, so it
                        // gets its full label and the whole width.
                        Expanded(
                          child: SecondaryButton(
                            text: _savingDraft
                                ? l10n.commonSaving
                                : _parkLabel(l10n),
                            icon: Icons.pause_circle_outline,
                            onPressed: (cart.isEmpty || _savingDraft)
                                ? null
                                : () => _park(inSheet: inSheet),
                          ),
                        ),
                    ],
                  ),
                  if (canFinalize)
                    _PrinterStatusLine(onConnect: _openPrinterSetup),
                ],
              ),
            ),
              ],
            ),
          ],
        ),
      );
    });
  }

  /// Wraps the cart-panel footer widgets. In the wide layout it returns a
  /// scrollable Flexible so the footer can never overflow (extra CGST/SGST /
  /// discount / previous-due rows scroll instead of clipping). In the bottom
  /// sheet the surrounding column is min-sized and the sheet scrolls itself, so
  /// the children render inline (a Flexible in an unbounded column would throw).
  /// The cart footer — payment mode, customer fields, discounts, totals and the
  /// action buttons.
  ///
  /// It is PINNED to the bottom and never scrolls: only the items list above it
  /// scrolls. Previously the footer was a loose [Flexible] wrapped in a
  /// [SingleChildScrollView], so it competed with the item list for vertical
  /// space — a long order pushed Payment Mode and the Save/WhatsApp buttons into
  /// their own scroll region, and the cashier had to scroll the panel to reach
  /// them. Keeping it fixed means the controls are always in the same place.
  ///
  /// In the bottom sheet the whole sheet scrolls, so the footer renders inline —
  /// which is the same min-sized column, hence no per-layout branch here.
  Widget _wrapFooter(List<Widget> children) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildCartRow(CartEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space16, vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  // Net (pre-tax) line amount — tax is shown in the totals below.
                  '₹${entry.lineNet(ref.read(gstEnabledProvider)).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _qtyButton(Icons.remove, () {
                  ref
                      .read(cartProvider.notifier)
                      .changeQty(entry.key, -1);
                }),
                _CartQtyField(
                  key: ValueKey('qty-${entry.key}'),
                  quantity: entry.quantity,
                  allowDecimal: entry.item.isMeasured,
                  onSubmitted: (q) =>
                      ref.read(cartProvider.notifier).setQty(entry.key, q),
                ),
                _qtyButton(Icons.add, () {
                  ref
                      .read(cartProvider.notifier)
                      .changeQty(entry.key, 1);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Editable quantity field for a cart row — tap to type an exact quantity.
// Self-contained controller so it survives cart-row rebuilds; commits on
// submit / focus-loss and reflects external +/- changes when not being edited.
// ---------------------------------------------------------------------------
class _CartQtyField extends StatefulWidget {
  final double quantity;
  final bool allowDecimal;
  final void Function(double) onSubmitted;

  const _CartQtyField({
    super.key,
    required this.quantity,
    required this.allowDecimal,
    required this.onSubmitted,
  });

  @override
  State<_CartQtyField> createState() => _CartQtyFieldState();
}

class _CartQtyFieldState extends State<_CartQtyField> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: formatQty(widget.quantity));
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // Select all on focus so typing replaces the value.
        _ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      } else {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(_CartQtyField old) {
    super.didUpdateWidget(old);
    // Reflect external +/- changes, but don't fight the user while editing.
    if (!_focus.hasFocus && widget.quantity != old.quantity) {
      _ctrl.text = formatQty(widget.quantity);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null) {
      // Invalid input — restore the last known good quantity.
      _ctrl.text = formatQty(widget.quantity);
      return;
    }
    if (v != widget.quantity) widget.onSubmitted(v);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.allowDecimal ? 48 : 36,
      height: 30,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: widget.allowDecimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _focus.unfocus(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OLD: Qty stepper (used by grid-card design) — kept for reference
// ---------------------------------------------------------------------------

// class _QtyStepper extends StatefulWidget {
//   final int qty;
//   final VoidCallback onRemove;
//   final VoidCallback onAdd;
//
//   const _QtyStepper({
//     super.key,
//     required this.qty,
//     required this.onRemove,
//     required this.onAdd,
//   });
//
//   @override
//   State<_QtyStepper> createState() => _QtyStepperState();
// }
//
// class _QtyStepperState extends State<_QtyStepper>
//     with SingleTickerProviderStateMixin {
//   late final AnimationController _bounce;
//   late final Animation<double> _scale;
//
//   @override
//   void initState() {
//     super.initState();
//     _bounce = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 180),
//     );
//     _scale = TweenSequence([
//       TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 1),
//       TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 1),
//     ]).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeOut));
//   }
//
//   @override
//   void didUpdateWidget(_QtyStepper old) {
//     super.didUpdateWidget(old);
//     if (old.qty != widget.qty) _bounce.forward(from: 0);
//   }
//
//   @override
//   void dispose() {
//     _bounce.dispose();
//     super.dispose();
//   }
//
//   Widget _btn(IconData icon, VoidCallback onTap) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         width: 32,
//         height: 32,
//         decoration: BoxDecoration(
//           gradient: AppColors.primaryGradient,
//           borderRadius: BorderRadius.circular(8),
//           boxShadow: [
//             BoxShadow(
//               color: AppColors.primary.withValues(alpha: 0.25),
//               blurRadius: 4,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Icon(icon, size: 16, color: Colors.white),
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         _btn(Icons.remove, widget.onRemove),
//         Expanded(
//           child: ScaleTransition(
//             scale: _scale,
//             child: Text(
//               '${widget.qty}',
//               textAlign: TextAlign.center,
//               style: const TextStyle(
//                 fontSize: 15,
//                 fontWeight: FontWeight.w800,
//                 color: AppColors.primary,
//               ),
//             ),
//           ),
//         ),
//         _btn(Icons.add, widget.onAdd),
//       ],
//     );
//   }
// }

// ---------------------------------------------------------------------------
// NEW: Excel-style table — one item per row, minimal height
// ---------------------------------------------------------------------------

class _ExcelItemTable extends StatelessWidget {
  final List<Item> items;
  final List<CartEntry> cart;
  final List<Widget> headerSlivers;
  final void Function(Item) onAdd;
  final void Function(Item) onDecrement;
  final void Function(Item) onIncrement;
  final void Function(Item, double) onSetQty;

  const _ExcelItemTable({
    required this.items,
    required this.cart,
    required this.headerSlivers,
    required this.onAdd,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSetQty,
  });

  Widget _header(AppLocalizations l10n) => Container(
        height: 28,
        color: AppColors.surfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const SizedBox(width: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.billingColItem,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  )),
            ),
            SizedBox(
              width: 72,
              child: Text(l10n.billingColPrice,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  )),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 112,
              child: Text(l10n.billingColQty,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  )),
            ),
          ],
        ),
      );

  // Total quantity for an item across all its cart lines (sums variants).
  double _qtyFor(String itemId) =>
      cart.where((e) => e.item.id == itemId).fold(0.0, (s, e) => s + e.quantity);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Two item columns only on large screens (≥1200px total) where the
    // items panel is wide enough to comfortably fit two side-by-side tables.
    final screenWidth = MediaQuery.of(context).size.width;
    final twoColumns = screenWidth >= 1200;

    if (!twoColumns) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ...headerSlivers,
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeaderDelegate(
              height: 29,
              child: Column(
                children: [
                  _header(l10n),
                  const Divider(height: 1),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 80),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 12, endIndent: 12),
              itemBuilder: (_, i) {
                final item = items[i];
                final qty = _qtyFor(item.id);
                return _ExcelItemRow(
                  index: i + 1,
                  item: item,
                  qty: qty,
                  onAdd: () => onAdd(item),
                  onDecrement: () => onDecrement(item),
                  onIncrement: () => onIncrement(item),
                  onSetQty: (v) => onSetQty(item, v),
                );
              },
            ),
          ),
        ],
      );
    }

    final rowCount = (items.length / 2).ceil();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        ...headerSlivers,
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeaderDelegate(
            height: 29,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _header(l10n)),
                    Container(width: 1, color: AppColors.border),
                    Expanded(child: _header(l10n)),
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 80),
          sliver: SliverList.separated(
            itemCount: rowCount,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 12, endIndent: 12),
            itemBuilder: (_, row) {
              final leftIndex = row * 2;
              final rightIndex = leftIndex + 1;
              final leftItem = items[leftIndex];
              final rightItem =
                  rightIndex < items.length ? items[rightIndex] : null;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ExcelItemRow(
                        index: leftIndex + 1,
                        item: leftItem,
                        qty: _qtyFor(leftItem.id),
                        onAdd: () => onAdd(leftItem),
                        onDecrement: () => onDecrement(leftItem),
                        onIncrement: () => onIncrement(leftItem),
                        onSetQty: (v) => onSetQty(leftItem, v),
                      ),
                    ),
                    Container(width: 1, color: AppColors.border),
                    Expanded(
                      child: rightItem == null
                          ? const SizedBox()
                          : _ExcelItemRow(
                              index: rightIndex + 1,
                              item: rightItem,
                              qty: _qtyFor(rightItem.id),
                              onAdd: () => onAdd(rightItem),
                              onDecrement: () => onDecrement(rightItem),
                              onIncrement: () => onIncrement(rightItem),
                              onSetQty: (v) => onSetQty(rightItem, v),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A header action rendered as a tinted tile: preview (blue) and clear (red).
///
/// Without the tint these read as flat grey glyphs and get missed — the header
/// is a dense row of title, count and controls. The tint is what makes them
/// look pressable, and it separates the two by consequence: blue looks at the
/// bill, red throws it away.
class _HeaderIconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  const _HeaderIconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final c = enabled ? color : AppColors.textDisabled;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.withValues(alpha: enabled ? 0.10 : 0.06),
        // A rounded square, not a circle: its straight right edge meets the
        // row's boundary, so the icon reads as aligned to it. A circle only
        // touches at one point and leaves the glyph looking inset. It also
        // echoes the cart tile at the other end of the same row.
        borderRadius: BorderRadius.circular(AppRadius.small),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 19, color: c),
          ),
        ),
      ),
    );
  }
}

/// The line under the settle button: whether a receipt can actually print, and
/// what to do about it when it can't.
///
/// This is shown ALWAYS, not only when something is wrong. A warning that only
/// appears on failure teaches nobody what the normal state looks like, and the
/// cashier needs to know before pressing — afterwards the customer has gone.
class _PrinterStatusLine extends ConsumerWidget {
  final VoidCallback onConnect;
  const _PrinterStatusLine({required this.onConnect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // A5/A4 output goes through the OS print dialog and needs no paired thermal
    // printer, so there is nothing useful to report about one.
    if (ref.watch(pdfPaperSelectedProvider)) return const SizedBox.shrink();

    final printer = ref.watch(activePrinterProvider).valueOrNull;
    final reachable = ref.watch(canPrintProvider).valueOrNull ?? false;

    final (String text, String? action, Color color) = switch ((printer, reachable)) {
      (null, _) => (l10n.billingPrinterNone, l10n.billingPrinterConnectOne,
          AppColors.warning),
      // Set up but not answering: Bluetooth off, out of range, powered down.
      (_, false) => (l10n.billingPrinterUnreachable, l10n.billingPrinterRetry,
          AppColors.warning),
      (final p, true) => (
          (p?.name?.trim().isNotEmpty ?? false)
              ? l10n.billingPrinterReadyNamed(p!.name!.trim())
              : l10n.billingPrinterReady,
          null,
          AppColors.success
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFont.style(fontSize: 11, color: color),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 5),
          InkWell(
            onTap: onConnect,
            child: Text(
              action,
              style: AppFont.style(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ]),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_PinnedHeaderDelegate old) =>
      old.height != height || old.child != child;
}

// ---------------------------------------------------------------------------
// Single row in the Excel table — animated highlight when in cart
// ---------------------------------------------------------------------------

class _ExcelItemRow extends StatefulWidget {
  final int index;
  final Item item;
  final double qty;
  final VoidCallback onAdd;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final void Function(double) onSetQty;
  // When set, the row represents a single size of [item]: it shows the size
  // label + price and uses the normal stepper/swipe (never the size picker).
  final ItemVariant? variant;

  const _ExcelItemRow({
    required this.index,
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSetQty,
    this.variant,
  });

  // Effective flags/labels — a variant row behaves like a plain (non-variant)
  // item so it gets the inline stepper and swipe gestures.
  bool get isVariantRow => variant != null;
  bool get treatAsVariantItem => variant == null && item.hasVariants;
  String get rowName => variant != null ? variant!.label : item.name;
  /// Null for a variant PARENT row: the item owns no price and its sizes differ,
  /// so no single figure is correct — [rowPriceLabel] shows their range instead.
  double? get rowPrice => variant?.price ?? item.price;

  /// What the price column renders. A size row and a plain item show their own
  /// price. A variant parent shows NOTHING: it owns no price and its sizes
  /// differ, so any single figure would be wrong — the price appears once the
  /// cashier picks a size.
  String get rowPriceLabel {
    if (treatAsVariantItem) return '';
    final p = rowPrice;
    if (p == null) return '';
    final suffix = item.isMeasured && !isVariantRow ? '/${item.unit}' : '';
    return '₹${p.toStringAsFixed(2)}$suffix';
  }

  @override
  State<_ExcelItemRow> createState() => _ExcelItemRowState();
}

class _ExcelItemRowState extends State<_ExcelItemRow>
    with TickerProviderStateMixin {
  late final AnimationController _swipeCtrl;
  late final TextEditingController _qtyTextCtrl;
  final FocusNode _qtyFocus = FocusNode();
  bool _editing = false;
  Timer? _debounce;

  // Track horizontal drag
  double _dragDx = 0;
  static const double _threshold = 56.0; // px to trigger action
  static const double _maxDrag = 72.0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _qtyTextCtrl = TextEditingController(
        text: widget.qty > 0 ? formatQty(widget.qty) : '');
  }

  @override
  void didUpdateWidget(_ExcelItemRow old) {
    super.didUpdateWidget(old);
    if (old.qty != widget.qty) {
      if (widget.qty == 0) {
        // Reset the field when the cart drops this row — but NOT while the user
        // is actively editing it. Otherwise typing a transient '0' or '.' (which
        // momentarily commits qty 0) would clear the field and steal focus.
        if (!_editing) {
          _qtyTextCtrl.text = '';
        }
      } else if (!_editing) {
        _qtyTextCtrl.text = formatQty(widget.qty);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _swipeCtrl.dispose();
    _qtyTextCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  /// Live commit while the user is still typing: only apply a valid positive
  /// quantity. A partial/zero value ('', '0', '.') is left untouched so the row
  /// keeps its cart membership — and its focus — until editing actually ends.
  void _commitLive() {
    final v = double.tryParse(_qtyTextCtrl.text.trim()) ?? 0.0;
    if (v > 0) widget.onSetQty(v);
  }

  /// Final commit when editing ends (focus lost / submitted). This is the only
  /// path allowed to set qty to 0 and drop the row from the cart.
  void _commitFinal() {
    _debounce?.cancel();
    _editing = false;
    final v = double.tryParse(_qtyTextCtrl.text.trim()) ?? 0.0;
    widget.onSetQty(v);
    if (v <= 0) _qtyTextCtrl.text = '';
  }

  Future<void> _snapBack() async {
    final begin = _dragDx;
    _dragDx = 0;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    final anim = Tween<double>(begin: begin, end: 0.0)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut));
    anim.addListener(() => setState(() => _dragDx = anim.value));
    await ctrl.forward();
    ctrl.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragDx = (_dragDx + d.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails d) async {
    if (_dragDx > _threshold) {
      // Swipe right → +
      HapticFeedback.lightImpact();
      await _snapBack();
      if (widget.qty > 0) {
        widget.onIncrement();
      } else {
        widget.onAdd();
      }
    } else if (_dragDx < -_threshold) {
      // Swipe left → −
      HapticFeedback.lightImpact();
      await _snapBack();
      if (widget.qty > 0) widget.onDecrement();
    } else {
      _snapBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inCart = widget.qty > 0;
    final revealRight = _dragDx > 8; // show + icon on right bg
    final revealLeft = _dragDx < -8; // show − icon on left bg

    return ClipRect(
      child: Stack(
        children: [
          // Background hint — green for +, red for −
          Positioned.fill(
            child: Row(
              children: [
                // Left background (minus)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: revealLeft ? (-_dragDx).clamp(0, _maxDrag) : 0,
                  color: AppColors.error.withValues(alpha: 0.12),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 10),
                  child: revealLeft
                      ? Icon(Icons.remove_circle_outline,
                          size: 18,
                          color: AppColors.error.withValues(
                              alpha: ((-_dragDx - 8) / (_threshold - 8))
                                  .clamp(0.0, 1.0)))
                      : null,
                ),
                const Spacer(),
                // Right background (plus)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: revealRight ? _dragDx.clamp(0, _maxDrag) : 0,
                  color: AppColors.primary.withValues(alpha: 0.10),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 10),
                  child: revealRight
                      ? Icon(Icons.add_circle_outline,
                          size: 18,
                          color: AppColors.primary.withValues(
                              alpha: ((_dragDx - 8) / (_threshold - 8))
                                  .clamp(0.0, 1.0)))
                      : null,
                ),
              ],
            ),
          ),
          // Draggable row content
          Transform.translate(
            offset: Offset(_dragDx, 0),
            child: GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 40,
                color: inCart
                    ? const Color(0xFFEEF2FF) // solid indigo-50
                    : AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Row number
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${widget.index}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Item name (or size label for a variant row)
                    Expanded(
                      child: Text(
                        widget.rowName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: inCart
                              ? AppColors.primaryDark
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Price (with /unit suffix for measured items)
                    SizedBox(
                      width: 72,
                      child: Text(
                        widget.rowPriceLabel,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Qty controls — same − / + stepper for all rows. A parent
                    // variant item (not a size row) has a read-only qty and
                    // opens the size picker; size rows and plain items edit inline.
                    SizedBox(
                      width: 112,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // − button
                          _GridBtn(
                            icon: Icons.remove,
                            enabled: inCart,
                            onTap: widget.onDecrement,
                          ),
                          // Editable qty field (read-only for a parent variant item)
                          Expanded(
                            child: GestureDetector(
                              // A parent variant item opens the size picker.
                              // Tapping the qty box of a plain row must NOT keep
                              // incrementing — it just starts editing. For an
                              // empty row we add qty 1 once, then focus so the
                              // user can immediately type the real quantity.
                              onTap: widget.treatAsVariantItem
                                  ? widget.onAdd
                                  : (!inCart
                                      ? () {
                                          widget.onAdd();
                                          _editing = true;
                                          // Reflect the added qty and select it so
                                          // the user can overwrite by just typing.
                                          _qtyTextCtrl.value = TextEditingValue(
                                            text: '1',
                                            selection:
                                                const TextSelection(
                                                    baseOffset: 0,
                                                    extentOffset: 1),
                                          );
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (mounted) {
                                              _qtyFocus.requestFocus();
                                            }
                                          });
                                        }
                                      : null),
                              child: SizedBox(
                                height: 28,
                                child: widget.treatAsVariantItem
                                    ? Center(
                                        child: Text(
                                          inCart ? formatQty(widget.qty) : '—',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: inCart
                                                ? AppColors.primary
                                                : AppColors.textDisabled,
                                          ),
                                        ),
                                      )
                                    : TextField(
                                        controller: _qtyTextCtrl,
                                        focusNode: _qtyFocus,
                                        enabled: inCart,
                                        textAlign: TextAlign.center,
                                        keyboardType: widget.item.isMeasured
                                            ? const TextInputType
                                                .numberWithOptions(decimal: true)
                                            : TextInputType.number,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: inCart
                                              ? AppColors.primary
                                              : AppColors.textDisabled,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 4),
                                          border: InputBorder.none,
                                          hintText: inCart ? '' : '—',
                                          hintStyle: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textDisabled,
                                          ),
                                        ),
                                        onTap: () => _editing = true,
                                        onChanged: (val) {
                                          _editing = true;
                                          _debounce?.cancel();
                                          // Only a valid positive number commits
                                          // live. Empty / '0' / '.' are left as-is
                                          // so the row keeps focus while typing.
                                          if ((double.tryParse(val.trim()) ?? 0) <=
                                              0) {
                                            return;
                                          }
                                          _debounce = Timer(
                                            const Duration(milliseconds: 400),
                                            _commitLive,
                                          );
                                        },
                                        onSubmitted: (_) => _commitFinal(),
                                        onEditingComplete: _commitFinal,
                                        onTapOutside: (_) => _commitFinal(),
                                      ),
                              ),
                            ),
                          ),
                          // + button
                          _GridBtn(
                            icon: Icons.add,
                            enabled: true,
                            onTap: inCart ? widget.onIncrement : widget.onAdd,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Small square icon button used in the Excel row
class _GridBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _GridBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? Colors.white : AppColors.textDisabled,
        ),
      ),
    );
  }
}


/// One additional-charge row in the cart panel: a description ("Delivery")
/// and an amount. Owns its own controllers and focus nodes so rows can be
/// added and removed independently; [key] lets the panel scroll the row above
/// the keyboard when either field is focused.
class _ChargeRow {
  final nameController = TextEditingController();
  final amountController = TextEditingController();
  final nameFocus = FocusNode();
  final amountFocus = FocusNode();
  final key = GlobalKey();

  String get name => nameController.text.trim();
  double get amount => double.tryParse(amountController.text.trim()) ?? 0.0;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
    nameFocus.dispose();
    amountFocus.dispose();
  }
}
