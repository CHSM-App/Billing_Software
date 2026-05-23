import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../api.dart';
import '../models/models.dart';
import '../models/cart_entry.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../services/printer_service.dart';
import '../services/offline_service.dart';
import '../services/sync_service.dart';
import '../storage.dart';
import 'login_screen.dart';

extension _StringEx on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class HomeScreen extends ConsumerStatefulWidget {
  final String? tableId;
  final String? tableNumber;
  final String? activeBillId;

  const HomeScreen(
      {super.key, this.tableId, this.tableNumber, this.activeBillId});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  String _selectedCategory = '';
  bool _showCustomerFields = false;
  String _paymentMode = 'cash';
  bool _generatingBill = false;
  bool _savingDraft = false;
  bool _draftLoaded = false;

  final _searchController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _barcodeBuffer = StringBuffer();
  DateTime? _lastKeyTime;

  // Animation for cart item add
  late final AnimationController _cartBadgeController;
  late final Animation<double> _cartBadgeAnim;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    if (widget.activeBillId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoadDraft());
    }
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);

    _cartBadgeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _cartBadgeAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _cartBadgeController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _cartBadgeController.dispose();
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final hasBarcodeScanner = ref.read(hasBarcodeProvider);
    bool isBarcodeActive;
    try {
      isBarcodeActive = Platform.isWindows && hasBarcodeScanner;
    } catch (_) {
      isBarcodeActive = false;
    }
    if (!isBarcodeActive) return false;

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

    if (event.logicalKey == LogicalKeyboardKey.enter) {
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
      _barcodeBuffer.write(char);
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
      final data = await getBill(widget.activeBillId!);
      final bill = Bill.fromJson(data);
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
            _customerPhoneController.text = bill.customerPhone!;
            _showCustomerFields = true;
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

  Future<void> _handleBarcodeScan(String barcode) async {
    if (barcode.isEmpty) return;
    try {
      final businessId = await getBusinessId();
      final cached = await OfflineService.instance
          .getCachedItemByBarcode(barcode, businessId ?? '');
      if (cached != null) {
        ref.read(cartProvider.notifier).addItem(cached);
        _animateCartBadge();
        return;
      }
      final data = await getItemByBarcode(barcode);
      ref.read(cartProvider.notifier).addItem(Item.fromJson(data));
      _animateCartBadge();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Item not found for barcode: $barcode', isError: true);
    }
  }

  void _animateCartBadge() {
    _cartBadgeController.forward(from: 0).then((_) {
      _cartBadgeController.reverse();
    });
  }

  List<Map<String, dynamic>> get _cartPayload {
    final cart = ref.read(cartProvider);
    return cart
        .map((e) => {'item_id': e.item.id, 'quantity': e.quantity})
        .toList();
  }

  Future<void> _saveDraft() async {
    final isOnline = ref.read(connectivityProvider);
    if (!isOnline) {
      _showSnack('Cannot save table draft while offline', isError: true);
      return;
    }
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack('Add at least one item first', isError: true);
      return;
    }
    setState(() => _savingDraft = true);
    try {
      if (widget.activeBillId != null) {
        await updateBillItems(widget.activeBillId!, _cartPayload);
      } else {
        await createBill({
          'items': _cartPayload,
          'table_id': widget.tableId,
          'payment_mode': _paymentMode,
          'status': 'draft',
        });
      }
      if (!mounted) return;
      _showSnack('Items saved. Table is now occupied.');
      Navigator.pop(context);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Failed to save. Check your connection.', isError: true);
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _generateBill() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack('Add at least one item to the cart', isError: true);
      return;
    }
    if (widget.activeBillId != null || widget.tableId != null) {
      await _generateBillOnline(cart);
      return;
    }
    await _generateBillOffline(cart);
    unawaited(SyncService.instance.syncAll().then((_) {
      ref.invalidate(reportProvider);
    }));
  }

  Future<void> _generateBillOnline(List<CartEntry> cart) async {
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
        });
        result = await finalizeBill(draft['id']);
      }
      final bill = Bill.fromJson(result);
      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      _customerNameController.clear();
      _customerPhoneController.clear();
      setState(() => _paymentMode = 'cash');
      ref.invalidate(reportProvider);
      _showBillDialog(bill);
      _autoPrint(bill);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Failed to generate bill. Check your connection.',
          isError: true);
    } finally {
      if (mounted) setState(() => _generatingBill = false);
    }
  }

  Future<void> _generateBillOffline(List<CartEntry> cart) async {
    setState(() => _generatingBill = true);
    try {
      final businessId = await getBusinessId() ?? '';
      final userId = await getUserId() ?? '';

      double subtotal = 0;
      double taxAmount = 0;
      final lineItems = cart.map((e) {
        final lineSub = e.item.price * e.quantity;
        final lineTax =
            e.item.taxRate != null ? lineSub * (e.item.taxRate! / 100) : 0.0;
        subtotal += lineSub;
        taxAmount += lineTax;
        return {
          'item_id': e.item.id,
          'item_name': e.item.name,
          'quantity': e.quantity.toDouble(),
          'unit_price': e.item.price,
          'tax_rate': e.item.taxRate,
          'line_total':
              double.parse((lineSub + lineTax).toStringAsFixed(2)),
        };
      }).toList();
      final total = double.parse((subtotal + taxAmount).toStringAsFixed(2));

      final localId = await OfflineService.instance.queueOfflineBill({
        'business_id': businessId,
        'user_id': userId,
        'table_id': widget.tableId,
        'customer_name': _customerNameController.text.trim().nullIfEmpty,
        'customer_phone': _customerPhoneController.text.trim().nullIfEmpty,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'total': total,
        'payment_mode': _paymentMode,
        'items_json': jsonEncode(lineItems),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final fakeBill = Bill(
        id: localId,
        businessId: businessId,
        billNumber: localId,
        tableId: widget.tableId,
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
      setState(() => _paymentMode = 'cash');
      if (!mounted) return;
      _showBillDialog(fakeBill);
      _autoPrint(fakeBill);
    } catch (e) {
      _showSnack('Failed to save bill offline: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generatingBill = false);
    }
  }

  Future<void> _autoPrint(Bill bill) async {
    final businessName = ref.read(businessNameProvider);
    try {
      await PrinterService.instance.printBill(bill, businessName: businessName);
    } on PrinterException catch (e) {
      if (e.message == 'No printer configured') return;
      if (mounted) _showSnack('Print failed: ${e.message}', isError: true);
    } catch (e) {
      if (mounted) _showSnack('Print failed: $e', isError: true);
    }
  }

  void _showBillDialog(Bill bill) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(AppSpacing.space24),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.large),
                    topRight: Radius.circular(AppRadius.large),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: AppSpacing.space12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bill Generated!',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Bill #${bill.billNumber}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Items
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space16),
                child: Column(
                  children: [
                    ...bill.items.map((item) => Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.itemName} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                ),
                              ),
                              Text(
                                '₹${item.lineTotal.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )),
                    const Divider(height: AppSpacing.space24),
                    if (bill.taxAmount > 0) ...[
                      _billRow('Subtotal',
                          '₹${bill.subtotal.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                      _billRow(
                          'Tax', '₹${bill.taxAmount.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                    ],
                    _billRow('Total', '₹${bill.total.toStringAsFixed(2)}',
                        bold: true),
                    const SizedBox(height: 4),
                    _billRow('Payment', bill.paymentMode.toUpperCase()),
                  ],
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space16),
                child: Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: 'Close',
                        onPressed: () {
                          Navigator.pop(context);
                          if (widget.tableId != null) Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space12),
                    Expanded(
                      child: PrimaryButton(
                        text: 'Print',
                        icon: Icons.print_outlined,
                        onPressed: () {
                          Navigator.pop(context);
                          _autoPrint(bill);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _billRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    )),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: bold ? AppColors.textPrimary : null,
                ),
          ),
        ],
      ),
    );
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

  Future<void> _logout() async {
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
      appBar: _buildAppBar(businessName, userName),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  AppBar _buildAppBar(String businessName, String userName) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(businessName, style: Theme.of(context).textTheme.titleLarge),
          if (widget.tableNumber != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Table ${widget.tableNumber}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
              ),
            ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.space8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(userName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            )),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_outlined, size: 20),
                tooltip: 'Logout',
                onPressed: _logout,
                color: AppColors.textSecondary,
              ),
            ],
          ),
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
      final count = ref.watch(cartItemCountProvider);
      return Stack(
        children: [
          _buildItemsPanel(),
          Positioned(
            bottom: AppSpacing.space16,
            right: AppSpacing.space16,
            child: ScaleTransition(
              scale: _cartBadgeAnim,
              child: FloatingActionButton.extended(
                onPressed: _openCartSheet,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 4,
                icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                label: Text(
                  count == 0 ? 'Cart' : 'Cart ($count)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      );
    });
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
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: _buildCartPanel(inSheet: true),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Items panel
  // ---------------------------------------------------------------------------

  Widget _buildItemsPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space12,
              AppSpacing.space12, AppSpacing.space12, AppSpacing.space8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search items…',
              prefixIcon: const Icon(Icons.search_outlined,
                  size: 18, color: AppColors.textSecondary),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: 12),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
        ),
        Consumer(builder: (context, ref, _) {
          final cats = ref.watch(categoriesProvider).valueOrNull ?? [];
          if (cats.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space12),
              itemCount: cats.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.space8),
              itemBuilder: (_, i) {
                final cat = cats[i];
                final selected = _selectedCategory == cat;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _selectedCategory =
                          _selectedCategory == cat ? '' : cat;
                    }),
                    backgroundColor: AppColors.surfaceVariant,
                    selectedColor: AppColors.primaryLight,
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.small)),
                  ),
                );
              },
            ),
          );
        }),
        const SizedBox(height: 4),
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Widget _buildItemList() {
    return Consumer(builder: (context, ref, _) {
      final itemsAsync = ref.watch(itemsProvider);
      final cart = ref.watch(cartProvider);

      return itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => NoInternetWidget(
          onRetry: () => ref.invalidate(itemsProvider),
        ),
        data: (allItems) {
          if (allItems.isEmpty && !ref.read(connectivityProvider)) {
            return NoInternetWidget(
              onRetry: () => ref.invalidate(itemsProvider),
            );
          }
          final items = _filteredItems(allItems);
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(itemsProvider);
                ref.invalidate(categoriesProvider);
                await ref.read(itemsProvider.future);
              },
              child: ListView(children: const [
                EmptyState(
                  icon: Icons.search_off_outlined,
                  message: 'No items found',
                ),
              ]),
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
              onAdd: (item) {
                ref.read(cartProvider.notifier).addItem(item);
                _animateCartBadge();
              },
              onDecrement: (item) =>
                  ref.read(cartProvider.notifier).changeQty(item.id, -1),
              onIncrement: (item) =>
                  ref.read(cartProvider.notifier).changeQty(item.id, 1),
              onSetQty: (item, qty) =>
                  ref.read(cartProvider.notifier).setQty(item.id, qty),
            ),
          );
        },
      );
    });
  }

  // ---------------------------------------------------------------------------
  // OLD grid-card design — kept for reference, commented out
  // ---------------------------------------------------------------------------

  // Widget _buildItemRow_OLD(Item item, List<CartEntry> cart) {
  //   final entry = cart.where((e) => e.item.id == item.id).firstOrNull;
  //   final qty = entry?.quantity ?? 0;
  //   final inCart = qty > 0;
  //
  //   return AnimatedContainer(
  //     duration: const Duration(milliseconds: 220),
  //     curve: Curves.easeInOut,
  //     margin: const EdgeInsets.symmetric(horizontal: 4),
  //     decoration: BoxDecoration(
  //       color: inCart ? AppColors.primaryLight : AppColors.surface,
  //       borderRadius: BorderRadius.circular(AppRadius.medium),
  //       border: Border.all(
  //         color: inCart ? AppColors.primary : AppColors.border,
  //         width: inCart ? 1.5 : 1,
  //       ),
  //       boxShadow: inCart ? AppShadow.small : [],
  //     ),
  //     child: Material(
  //       color: Colors.transparent,
  //       borderRadius: BorderRadius.circular(AppRadius.medium),
  //       child: InkWell(
  //         onTap: inCart
  //             ? null
  //             : () {
  //                 ref.read(cartProvider.notifier).addItem(item);
  //                 _animateCartBadge();
  //               },
  //         borderRadius: BorderRadius.circular(AppRadius.medium),
  //         child: Padding(
  //           padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //             children: [
  //               Row(
  //                 crossAxisAlignment: CrossAxisAlignment.center,
  //                 children: [
  //                   Expanded(
  //                     child: Text(
  //                       item.name,
  //                       style: TextStyle(
  //                         fontSize: 13,
  //                         fontWeight: FontWeight.w600,
  //                         color: inCart ? AppColors.primaryDark : AppColors.textPrimary,
  //                         height: 1.2,
  //                       ),
  //                       maxLines: 1,
  //                       overflow: TextOverflow.ellipsis,
  //                     ),
  //                   ),
  //                   const SizedBox(width: 6),
  //                   AnimatedContainer(
  //                     duration: const Duration(milliseconds: 220),
  //                     padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  //                     decoration: BoxDecoration(
  //                       color: inCart
  //                           ? AppColors.primary.withValues(alpha: 0.12)
  //                           : AppColors.surfaceVariant,
  //                       borderRadius: BorderRadius.circular(20),
  //                     ),
  //                     child: Text(
  //                       '₹${item.price.toStringAsFixed(2)}',
  //                       style: TextStyle(
  //                         fontSize: 11,
  //                         fontWeight: FontWeight.w700,
  //                         color: inCart ? AppColors.primary : AppColors.textSecondary,
  //                       ),
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //               const SizedBox(height: 6),
  //               AnimatedSwitcher(
  //                 duration: const Duration(milliseconds: 220),
  //                 switchInCurve: Curves.easeOut,
  //                 switchOutCurve: Curves.easeIn,
  //                 transitionBuilder: (child, anim) => ScaleTransition(
  //                   scale: anim,
  //                   child: FadeTransition(opacity: anim, child: child),
  //                 ),
  //                 child: inCart
  //                     ? _QtyStepper(
  //                         key: ValueKey('stepper_${item.id}'),
  //                         qty: qty,
  //                         onRemove: () => ref.read(cartProvider.notifier).changeQty(item.id, -1),
  //                         onAdd: () => ref.read(cartProvider.notifier).addItem(item),
  //                       )
  //                     : SizedBox(
  //                         key: ValueKey('add_${item.id}'),
  //                         width: double.infinity,
  //                         height: 32,
  //                         child: DecoratedBox(
  //                           decoration: BoxDecoration(
  //                             gradient: AppColors.primaryGradient,
  //                             borderRadius: BorderRadius.circular(8),
  //                             boxShadow: [
  //                               BoxShadow(
  //                                 color: AppColors.primary.withValues(alpha: 0.22),
  //                                 blurRadius: 6,
  //                                 offset: const Offset(0, 2),
  //                               ),
  //                             ],
  //                           ),
  //                           child: const Center(
  //                             child: Row(
  //                               mainAxisSize: MainAxisSize.min,
  //                               children: [
  //                                 Icon(Icons.add, size: 14, color: Colors.white),
  //                                 SizedBox(width: 4),
  //                                 Text(
  //                                   'Add',
  //                                   style: TextStyle(
  //                                     fontSize: 12,
  //                                     fontWeight: FontWeight.w700,
  //                                     color: Colors.white,
  //                                     letterSpacing: 0.3,
  //                                   ),
  //                                 ),
  //                               ],
  //                             ),
  //                           ),
  //                         ),
  //                       ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }


  // ---------------------------------------------------------------------------
  // Cart panel
  // ---------------------------------------------------------------------------

  Widget _buildCartPanel({bool inSheet = false}) {
    return Consumer(builder: (context, ref, _) {
      final cart = ref.watch(cartProvider);
      final subtotal = ref.watch(cartSubtotalProvider);
      final tax = ref.watch(cartTaxProvider);
      final total = ref.watch(cartTotalProvider);

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
                  Text('Order',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (cart.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(cartProvider.notifier).clear(),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ),
            ),
            if (cart.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.space32,
                    horizontal: AppSpacing.space16),
                child: Column(
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
                    Text('No items added yet',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            else
              ...cart.map((e) => _buildCartRow(e)),

            if (cart.isNotEmpty) ...[
              const Divider(height: 1),
              Container(
                margin: const EdgeInsets.all(AppSpacing.space12),
                padding: const EdgeInsets.all(AppSpacing.space12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Column(
                  children: [
                    if (tax > 0) ...[
                      _totalRow(
                          'Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                      _totalRow('Tax', '₹${tax.toStringAsFixed(2)}'),
                      const Divider(height: AppSpacing.space12),
                    ],
                    _totalRow('Total', '₹${total.toStringAsFixed(2)}',
                        bold: true),
                  ],
                ),
              ),
            ],

            const Divider(height: 1),

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
                          Text(
                            'Customer details (optional)',
                            style:
                                Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                          const Spacer(),
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
                                  label: 'Customer name',
                                  controller: _customerNameController,
                                  prefixIcon: const Icon(Icons.person_outline,
                                      size: 16,
                                      color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: AppSpacing.space8),
                                AppTextField(
                                  label: 'Customer phone',
                                  controller: _customerPhoneController,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 10,
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

            // Payment mode
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16),
              child: DropdownButtonFormField<String>(
                initialValue: _paymentMode,
                decoration: const InputDecoration(
                  labelText: 'Payment mode',
                  prefixIcon: Icon(Icons.payments_outlined,
                      size: 18, color: AppColors.textSecondary),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(
                      value: 'credit', child: Text('Credit')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _paymentMode = v!),
              ),
            ),

            if (widget.tableId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                    AppSpacing.space12, AppSpacing.space16, 0),
                child: SecondaryButton(
                  text: _savingDraft ? 'Saving…' : 'Save Draft',
                  icon: Icons.save_outlined,
                  onPressed:
                      (cart.isEmpty || _savingDraft) ? null : _saveDraft,
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space16),
              child: PrimaryButton(
                text: 'Generate Bill',
                icon: Icons.receipt_long_outlined,
                onPressed: cart.isEmpty ? null : _generateBill,
                isLoading: _generatingBill,
              ),
            ),
          ],
        ),
      );
    });
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
                Text(entry.item.name,
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
                      .changeQty(entry.item.id, -1);
                }),
                SizedBox(
                  width: 32,
                  child: Text('${entry.quantity}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                ),
                _qtyButton(Icons.add, () {
                  ref
                      .read(cartProvider.notifier)
                      .changeQty(entry.item.id, 1);
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

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: bold ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppColors.primary : AppColors.textPrimary,
              ),
        ),
      ],
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
  final void Function(Item) onAdd;
  final void Function(Item) onDecrement;
  final void Function(Item) onIncrement;
  final void Function(Item, int) onSetQty;

  const _ExcelItemTable({
    required this.items,
    required this.cart,
    required this.onAdd,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSetQty,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row
        Container(
          height: 28,
          color: AppColors.surfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const SizedBox(width: 24), // # column
              const SizedBox(width: 8),
              Expanded(
                child: Text('Item',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    )),
              ),
              SizedBox(
                width: 72,
                child: Text('Price',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    )),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: Text('Qty',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    )),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 12, endIndent: 12),
            itemBuilder: (_, i) {
              final item = items[i];
              final entry =
                  cart.where((e) => e.item.id == item.id).firstOrNull;
              final qty = entry?.quantity ?? 0;
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
}

// ---------------------------------------------------------------------------
// Single row in the Excel table — animated highlight when in cart
// ---------------------------------------------------------------------------

class _ExcelItemRow extends StatefulWidget {
  final int index;
  final Item item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final void Function(int) onSetQty;

  const _ExcelItemRow({
    required this.index,
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSetQty,
  });

  @override
  State<_ExcelItemRow> createState() => _ExcelItemRowState();
}

class _ExcelItemRowState extends State<_ExcelItemRow>
    with TickerProviderStateMixin {
  late final AnimationController _swipeCtrl;
  late final TextEditingController _qtyTextCtrl;
  bool _editing = false;

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
    _qtyTextCtrl =
        TextEditingController(text: widget.qty > 0 ? '${widget.qty}' : '');
  }

  @override
  void didUpdateWidget(_ExcelItemRow old) {
    super.didUpdateWidget(old);
    if (old.qty != widget.qty && !_editing) {
      _qtyTextCtrl.text = widget.qty > 0 ? '${widget.qty}' : '';
    }
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    _qtyTextCtrl.dispose();
    super.dispose();
  }

  void _commitText() {
    _editing = false;
    final v = int.tryParse(_qtyTextCtrl.text.trim()) ?? 0;
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
                    // Item name
                    Expanded(
                      child: Text(
                        widget.item.name,
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
                    // Price
                    SizedBox(
                      width: 72,
                      child: Text(
                        '₹${widget.item.price.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Qty controls
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
                          // Editable qty field
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (!inCart) widget.onAdd();
                              },
                              child: SizedBox(
                                height: 28,
                                child: TextField(
                                  controller: _qtyTextCtrl,
                                  enabled: inCart,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
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
                                        const EdgeInsets.symmetric(vertical: 4),
                                    border: InputBorder.none,
                                    hintText: inCart ? '' : '—',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textDisabled,
                                    ),
                                  ),
                                  onTap: () => _editing = true,
                                  onSubmitted: (_) => _commitText(),
                                  onEditingComplete: _commitText,
                                  onTapOutside: (_) => _commitText(),
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

