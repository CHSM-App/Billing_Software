import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../models/cart_entry.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/skeletons.dart';
import '../services/printer_service.dart';
import '../services/receipt_output.dart';
import '../services/receipt_labels.dart';
import '../services/offline_service.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../storage.dart';
import '../main.dart' show rootMessengerKey;
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
  final _discountPctKey = GlobalKey();
  final _discountAmtKey = GlobalKey();

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
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _discountPctController.dispose();
    _discountAmtController.dispose();
    _customerNameFocus.dispose();
    _customerPhoneFocus.dispose();
    _discountPctFocus.dispose();
    _discountAmtFocus.dispose();
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

  void _onDiscountPctChanged() {
    if (_updatingDiscount) return;
    final total = ref.read(cartTotalProvider);
    final pct = double.tryParse(_discountPctController.text) ?? 0;
    _updatingDiscount = true;
    final amt = total > 0 && pct > 0 ? (total * pct / 100) : 0.0;
    _discountAmtController.text = amt > 0 ? amt.toStringAsFixed(2) : '';
    _updatingDiscount = false;
    setState(() {});
  }

  void _onDiscountAmtChanged() {
    if (_updatingDiscount) return;
    final total = ref.read(cartTotalProvider);
    final amt = double.tryParse(_discountAmtController.text) ?? 0;
    _updatingDiscount = true;
    final pct = total > 0 && amt > 0 ? (amt / total * 100) : 0.0;
    _discountPctController.text = pct > 0 ? pct.toStringAsFixed(2) : '';
    _updatingDiscount = false;
    setState(() {});
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    if (barcode.isEmpty) return;
    final l10n = context.l10n;
    try {
      final businessId = await getBusinessId();
      final cached = await OfflineService.instance
          .getBarcodeMatch(barcode, businessId ?? '');
      if (cached != null) {
        ref
            .read(cartProvider.notifier)
            .addItem(cached.item, variant: cached.variant);
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
      ref.read(cartProvider.notifier).addItem(item, variant: variant);
      // _animateCartBadge();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack(l10n.billingItemNotFoundBarcode(barcode), isError: true);
    }
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
    }
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
      final billPrefix = await getBillPrefix();

      double subtotal = 0;
      double taxAmount = 0;
      final lineItems = cart.map((e) {
        final lineSub = e.effectivePrice * e.quantity;
        final lineTax =
            e.item.taxRate != null ? lineSub * (e.item.taxRate! / 100) : 0.0;
        subtotal += lineSub;
        taxAmount += lineTax;
        return {
          'item_id': e.item.id,
          'variant_id': e.variant?.id,
          'item_name': e.displayName,
          'quantity': e.quantity,
          'unit_price': e.effectivePrice,
          'tax_rate': e.item.taxRate,
          'line_total': double.parse((lineSub + lineTax).toStringAsFixed(2)),
        };
      }).toList();
      final total = double.parse((subtotal + taxAmount).toStringAsFixed(2));
      final discountAmt =
          (double.tryParse(_discountAmtController.text) ?? 0.0).clamp(0.0, total);
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
        'total': total,
        'payment_mode': _paymentMode,
        'items_json': jsonEncode(lineItems),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final localId = queued.localId;
      final ts = localId.replaceAll(RegExp(r'\D'), '');
      final draftNumber =
          '$billPrefix-${ts.length > 6 ? ts.substring(ts.length - 6) : ts}';

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
      _showSnack(l10n.billingDraftSaved);

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
    _showSnack(l10n.billingDraftSaved);
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
      // This screen stays alive (nothing was popped), so reset the saving flag
      // ourselves — otherwise the Save Draft FAB spins forever.
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
    if (_blockedUnsyncedLocalDraft()) return;
    if (!_validateCustomerPhone()) return;
    if (!_validateCreditCustomer()) return;
    if (widget.activeBillId != null || widget.tableId != null) {
      // Table billing — always online
      await _generateBillOnline(cart, onBillReady: onBillReady);
      return;
    }
    // Retail billing — online when connected, offline when not
    final isOnline = ref.read(connectivityProvider);
    if (isOnline) {
      await _generateBillOnline(cart, onBillReady: onBillReady);
    } else {
      await _generateBillOffline(cart, onBillReady: onBillReady);
      unawaited(SyncService.instance.syncAll().then((_) {
        ref.invalidate(reportProvider);
      }));
    }
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
      if (widget.activeBillId != null) {
        await updateBillItems(widget.activeBillId!, _cartPayload);
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
      if (onBillReady != null) {
        onBillReady(bill);
      } else {
        _navigateAfterBill();
      }
    } on ApiException catch (e) {
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
      // Use the business's real invoice prefix for the offline receipt so the
      // number doesn't visibly change (no "LOCAL-") when offline. The server
      // assigns the authoritative sequence number on sync.
      final billPrefix = await getBillPrefix();

      double subtotal = 0;
      double taxAmount = 0;
      final lineItems = cart.map((e) {
        final lineSub = e.effectivePrice * e.quantity;
        final lineTax =
            e.item.taxRate != null ? lineSub * (e.item.taxRate! / 100) : 0.0;
        subtotal += lineSub;
        taxAmount += lineTax;
        return {
          'item_id': e.item.id,
          'variant_id': e.variant?.id,
          'item_name': e.displayName,
          'quantity': e.quantity,
          'unit_price': e.effectivePrice,
          'tax_rate': e.item.taxRate,
          'line_total':
              double.parse((lineSub + lineTax).toStringAsFixed(2)),
        };
      }).toList();
      final total = double.parse((subtotal + taxAmount).toStringAsFixed(2));
      final discountAmt = (double.tryParse(_discountAmtController.text) ?? 0.0)
          .clamp(0.0, total);

      final queued = await OfflineService.instance.queueOfflineBill({
        'business_id': businessId,
        'user_id': userId,
        'table_id': widget.tableId,
        'customer_name': _customerNameController.text.trim().nullIfEmpty,
        'customer_phone': _customerPhoneController.text.trim().nullIfEmpty,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmt,
        'total': total,
        'payment_mode': _paymentMode,
        'items_json': jsonEncode(lineItems),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final localId = queued.localId;
      // Display number keeps the real prefix; the last 6 digits of the queue
      // timestamp keep it unique locally until the server assigns the final one.
      final ts = localId.replaceAll(RegExp(r'\D'), '');
      final offlineBillNumber =
          '$billPrefix-${ts.length > 6 ? ts.substring(ts.length - 6) : ts}';

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
        total: total,
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
      setState(() => _paymentMode = 'cash');
      if (!mounted) return;
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

  Future<void> _autoPrint(Bill bill) async {
    final l10n = context.l10n;
    final businessName = ref.read(businessNameProvider);
    final labels = ReceiptLabels.from(l10n, ref.read(localeProvider).code);
    // Address and FSSAI print whenever available, regardless of GST. GSTIN
    // remains gated on GST being enabled (gstin stays null when off, so a
    // non-GST receipt is byte-for-byte as before).
    final profile = await getGstProfile();
    final addr = profile['business_address'] ?? '';
    final fss = profile['fssai_number'] ?? '';
    final String? address = addr.isNotEmpty ? addr : null;
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
          // Save Draft + Cart row. Shown whenever the cart has items — for
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
                        _savingDraft ? l10n.commonSaving : l10n.billingSaveDraft,
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

  /// Empty-cart placeholder. When [flexible] (wide layout) it expands to fill
  /// the space the cart list would occupy so the footer actions stay pinned to
  /// the bottom and never overflow. In the bottom sheet it stays intrinsic.
  Widget _emptyCartPlaceholder(AppLocalizations l10n, {required bool flexible}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.space32, horizontal: AppSpacing.space16),
      child: Column(
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
    );
    if (!flexible) return content;
    // Center the placeholder within the flexible space; a scroll view guards
    // against overflow if the panel is ever shorter than the placeholder.
    return Expanded(
      child: SingleChildScrollView(
        child: Center(child: content),
      ),
    );
  }

  /// Build the CGST/SGST rows for the cart totals when GST is enabled.
  /// Each is half the [tax]; the rate is derived from the taxable [subtotal]
  /// (e.g. 18% GST → CGST 9% / SGST 9%). Returns (label, amount) pairs.
  List<(String, String)> _gstSplitRows(
      AppLocalizations l10n, double subtotal, double tax) {
    final half = (tax / 2).toStringAsFixed(2);
    // Effective half-rate for the label; blank-safe when subtotal is 0.
    String rate = '';
    if (subtotal > 0) {
      final r = tax / subtotal * 100 / 2;
      rate = r % 1 == 0 ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
    }
    return [
      (l10n.billingCgst(rate), half),
      (l10n.billingSgst(rate), half),
    ];
  }

  Widget _buildCartPanel({bool inSheet = false}) {
    return Consumer(builder: (context, ref, _) {
      final l10n = context.l10n;
      final cart = ref.watch(cartProvider);
      final subtotal = ref.watch(cartSubtotalProvider);
      final tax = ref.watch(cartTaxProvider);
      final total = ref.watch(cartTotalProvider);
      // When GST is enabled, the tax is shown split as CGST + SGST (each half)
      // in the totals summary below, mirroring the printed receipt.
      final gstEnabled = ref.watch(gstEnabledProvider);
      // A server takes/builds orders and sends them to the kitchen but cannot
      // finalize or take payment — hide the finalize (WhatsApp/Print) actions.
      final canFinalize = ref.watch(userRoleProvider) != 'server';
      // Can we actually print right now (printer configured AND Bluetooth on)?
      // If not, the primary action becomes "Save" (finalize without printing)
      // and a compact hint offers a link to connect. Re-checked on app resume.
      final hasPrinter = ref.watch(printReadyProvider);

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
            // Header — always visible
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
                  Flexible(
                    child: Text(l10n.billingOrder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  const Spacer(),
                  // Clearing a cart / releasing a table is a cashier/owner
                  // action — hidden for servers, who only build orders.
                  if (cart.isNotEmpty && canFinalize)
                    TextButton.icon(
                      onPressed: () => _clearCart(inSheet: inSheet),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: Text(l10n.commonClear,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ),
            ),

            // Scrollable cart items — takes all available space
            if (cart.isEmpty)
              // In the wide layout the empty placeholder must FLEX so it absorbs
              // the leftover vertical space; a fixed-height placeholder here is
              // what pushed the footer actions off-screen (bottom overflow).
              // In the bottom sheet the column is min-sized, so keep it fixed.
              _emptyCartPlaceholder(l10n, flexible: !inSheet)
            else if (inSheet)
              // In bottom sheet: not constrained, just list
              Column(
                mainAxisSize: MainAxisSize.min,
                children: cart.map((e) => _buildCartRow(e)).toList(),
              )
            else
              // In wide layout: scrollable list that takes remaining space
              Expanded(
                child: ListView(
                  children: cart.map((e) => _buildCartRow(e)).toList(),
                ),
              ),

            // Footer (payment, customer, discount, totals, actions). In the wide
            // layout it's wrapped in a scrollable Flexible so it can never
            // overflow the panel — on a short window, or when extra rows appear
            // (CGST/SGST, discount, previous due), the footer scrolls instead of
            // clipping. In the bottom sheet the column is already min-sized and
            // the sheet scrolls, so the footer renders inline (a Flexible in an
            // unbounded column would be a layout error there).
            _wrapFooter(
              inSheet,
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

            // Bill summary
            if (cart.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                    AppSpacing.space12, AppSpacing.space16, 0),
                child: Builder(builder: (ctx) {
                  final discountAmt =
                      (double.tryParse(_discountAmtController.text) ?? 0.0)
                          .clamp(0.0, total);
                  // When "clear previous credit" is on, the old due is added to
                  // this bill's payable, so the customer pays one combined
                  // amount and those old bills are settled on finalize.
                  final prevDue =
                      _settlePrevCredit ? _prevCreditDue : 0.0;
                  final netPayable = total - discountAmt + prevDue;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Column(
                      children: [
                        // Total Amount row
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space12, vertical: 10),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  l10n.billingTotalAmount,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ),
                              const Spacer(),
                              // The compact "+ GST" hint is only shown when GST
                              // is NOT enabled; with GST on, the split is broken
                              // out in its own CGST/SGST rows below.
                              if (tax > 0 && !gstEnabled)
                                Flexible(
                                  child: Text(
                                    l10n.billingSubtotalPlusGst(
                                        subtotal.toStringAsFixed(2),
                                        tax.toStringAsFixed(2)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
                                  ),
                                ),
                              if (tax > 0 && !gstEnabled) const SizedBox(width: 6),
                              Text(
                                '₹${total.toStringAsFixed(2)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        // CGST / SGST split — shown when GST is enabled and the
                        // cart carries tax. Each is half the tax; the rate is
                        // derived from the taxable subtotal (e.g. 18% → 9%+9%).
                        // Kept in one compact block (single divider, tight rows)
                        // so it never pushes the footer actions off-screen.
                        if (gstEnabled && tax > 0) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final line
                                    in _gstSplitRows(l10n, subtotal, tax))
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Text(
                                          line.$1,
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '₹${line.$2}',
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        // Discount row — only when applied
                        if (discountAmt > 0) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: 10),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    l10n.billingDiscountApplied,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '− ₹${discountAmt.toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF16A34A),
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
                                Flexible(
                                  child: Text(
                                    l10n.billingPreviousDue,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '+ ₹${prevDue.toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.warning,
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
                              topLeft: discountAmt > 0
                                  ? Radius.zero
                                  : Radius.circular(AppRadius.small - 1),
                              topRight: discountAmt > 0
                                  ? Radius.zero
                                  : Radius.circular(AppRadius.small - 1),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space12, vertical: 11),
                          child: Row(
                            children: [
                              Flexible(
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
                              const Spacer(),
                              Text(
                                '₹${netPayable.toStringAsFixed(2)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(ctx)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
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

            // Save Draft is available to everyone — for tables and for
            // table-less "open orders" on the standalone billing page.
            Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.space16,
                    AppSpacing.space12,
                    AppSpacing.space16,
                    // When this is the only action (a server with no finalize
                    // row), add the bottom safe-area inset here instead.
                    canFinalize ? 0 : AppSpacing.space16 + MediaQuery.of(context).padding.bottom),
                child: SecondaryButton(
                  text: _savingDraft ? l10n.commonSaving : l10n.billingSaveDraft,
                  icon: Icons.save_outlined,
                  onPressed: (cart.isEmpty || _savingDraft)
                      ? null
                      : () {
                          // This button lives inside the cart bottom sheet.
                          // Close the sheet first so _saveDraft's Navigator.pop
                          // pops the billing screen (not the sheet) and the
                          // Tables list is what the user returns to.
                          if (inSheet) Navigator.pop(context);
                          _saveDraft();
                        },
                ),
              ),

            if (canFinalize)
              Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.space16,
                AppSpacing.space16,
                AppSpacing.space16,
                AppSpacing.space16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Compact printer hint — shown only when no printer is set up.
                  // Kept to a single small red line so it never crowds the UI;
                  // "Connect" links straight to printer setup.
                  if (!hasPrinter)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.print_disabled_outlined,
                              size: 13, color: AppColors.error),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                text: l10n.billingPrinterNotConnected,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.error,
                                ),
                                children: [
                                  const TextSpan(text: ' '),
                                  TextSpan(
                                    text: l10n.billingPrinterConnect,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = _openPrinterSetup,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.message_outlined,
                        size: 16,
                        color: (cart.isEmpty || _generatingBill)
                            ? AppColors.textSecondary
                            : const Color(0xFF25D366),
                      ),
                      label: Text(
                        l10n.billingWhatsapp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          color: (cart.isEmpty || _generatingBill)
                              ? AppColors.textSecondary
                              : const Color(0xFF25D366),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: (cart.isEmpty || _generatingBill)
                              ? AppColors.textSecondary
                              : const Color(0xFF25D366),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.small),
                        ),
                      ),
                      onPressed: (cart.isEmpty || _generatingBill)
                          ? null
                          : () {
                              // Credit needs name + phone. Validate BEFORE
                              // popping so the card stays open with the inline
                              // message (same pattern as the phone guard below).
                              if (!_validateCreditCustomer()) return;
                              // WhatsApp needs a phone. Without one, don't
                              // finalize/clear the bill — prompt for the number.
                              if (!_ensureCustomerPhoneForWhatsApp()) return;
                              if (inSheet) Navigator.pop(context);
                              _generateBillAndWhatsApp();
                            },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: PrimaryButton(
                      // With a printer set up the primary action prints the
                      // receipt; without one it just saves (finalizes) the bill
                      // so the sale is never blocked on printer setup.
                      text: hasPrinter ? l10n.commonPrint : l10n.commonSave,
                      icon: hasPrinter
                          ? Icons.print_outlined
                          : Icons.save_outlined,
                      onPressed: (cart.isEmpty || _generatingBill)
                          ? null
                          : () {
                              // Credit needs name + phone. Validate BEFORE
                              // popping so the card stays open with the inline
                              // message instead of closing then failing.
                              if (!_validateCreditCustomer()) return;
                              if (inSheet) Navigator.pop(context);
                              if (hasPrinter) {
                                _generateBillAndPrint();
                              } else {
                                // No printer — finalize without printing.
                                _generateBill(onBillReady: (_) {
                                  _navigateAfterBill();
                                });
                              }
                            },
                      isLoading: _generatingBill,
                    ),
                  ),
                    ],
                  ),
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
  Widget _wrapFooter(bool inSheet, List<Widget> children) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (inSheet) return column;
    return Flexible(
      fit: FlexFit.loose,
      child: SingleChildScrollView(child: column),
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
                  '₹${entry.lineTotal.toStringAsFixed(2)}',
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
  double get rowPrice => variant?.price ?? item.price;

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
                          fontWeight:
                              inCart ? FontWeight.w600 : FontWeight.w400,
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
                        (widget.item.isMeasured && !widget.isVariantRow)
                            ? '₹${widget.rowPrice.toStringAsFixed(2)}/${widget.item.unit}'
                            : '₹${widget.rowPrice.toStringAsFixed(2)}',
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

