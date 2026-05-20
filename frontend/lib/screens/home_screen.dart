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

  const HomeScreen({super.key, this.tableId, this.tableNumber, this.activeBillId});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Local UI state only
  String _selectedCategory = '';
  bool _showCustomerFields = false;
  String _paymentMode = 'cash';
  bool _generatingBill = false;
  bool _savingDraft = false;
  bool _draftLoaded = false;

  // Controllers
  final _searchController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _barcodeBuffer = StringBuffer();
  DateTime? _lastKeyTime;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    // Load draft bill into cart once items are available
    if (widget.activeBillId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoadDraft());
    }
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Only active when barcode scanner is enabled (Windows retail)
    final hasBarcodeScanner = ref.read(hasBarcodeProvider);
    bool isBarcodeActive;
    try {
      isBarcodeActive = Platform.isWindows && hasBarcodeScanner;
    } catch (_) {
      isBarcodeActive = false;
    }
    if (!isBarcodeActive) return false;

    // If a text input has focus, let keys pass through so the user can type
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus?.context != null) {
      // Check if the focused widget is inside a TextField/EditableText
      bool isTextField = false;
      primaryFocus!.context!.visitAncestorElements((element) {
        if (element.widget is EditableText) {
          isTextField = true;
          return false; // stop visiting
        }
        return true;
      });
      if (isTextField) return false;
    }

    final now = DateTime.now();
    // Reset buffer if gap between keystrokes is too long (> 100ms = human typing)
    if (_lastKeyTime != null && now.difference(_lastKeyTime!).inMilliseconds > 100) {
      _barcodeBuffer.clear();
    }
    _lastKeyTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final code = _barcodeBuffer.toString().trim();
      _barcodeBuffer.clear();
      _lastKeyTime = null;
      if (code.isNotEmpty) {
        // Unfocus everything so ENTER doesn't also trigger focused buttons/tiles
        primaryFocus?.unfocus();
        _handleBarcodeScan(code);
      }
      return true; // consume ENTER always to prevent nav
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _barcodeBuffer.write(char);
      return true; // consume digit keys to prevent button activation
    }

    return false;
  }

  Future<void> _tryLoadDraft() async {
    if (_draftLoaded || widget.activeBillId == null) return;
    final itemsAsync = ref.read(itemsProvider);
    if (!itemsAsync.hasValue) {
      // Wait for items to load then retry
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
    } catch (_) {
      // Non-fatal — start with empty cart
    }
  }

  List<Item> _filteredItems(List<Item> allItems) {
    final query = _searchController.text.toLowerCase();
    return allItems.where((item) {
      if (!item.isActive) return false;
      final matchesSearch = query.isEmpty || item.name.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategory.isEmpty || item.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Barcode scanner
  // ---------------------------------------------------------------------------

  Future<void> _handleBarcodeScan(String barcode) async {
    if (barcode.isEmpty) return;
    final isOnline = ref.read(connectivityProvider);
    try {
      if (isOnline) {
        final data = await getItemByBarcode(barcode);
        ref.read(cartProvider.notifier).addItem(Item.fromJson(data));
      } else {
        final businessId = await getBusinessId();
        final item = await OfflineService.instance
            .getCachedItemByBarcode(barcode, businessId ?? '');
        if (item == null) {
          _showSnack('Item not found for barcode: $barcode', isError: true);
          return;
        }
        ref.read(cartProvider.notifier).addItem(item);
      }
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Item not found for barcode: $barcode', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Cart helpers
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> get _cartPayload {
    final cart = ref.read(cartProvider);
    return cart.map((e) => {'item_id': e.item.id, 'quantity': e.quantity}).toList();
  }

  // ---------------------------------------------------------------------------
  // Draft save
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Generate bill
  // ---------------------------------------------------------------------------

  Future<void> _generateBill() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack('Add at least one item to the cart', isError: true);
      return;
    }

    final isOnline = ref.read(connectivityProvider);
    if (!isOnline) {
      await _generateBillOffline(cart);
      return;
    }

    setState(() => _generatingBill = true);
    try {
      Map<String, dynamic> result;

      if (widget.activeBillId != null) {
        await updateBillItems(widget.activeBillId!, _cartPayload);
        result = await finalizeBill(widget.activeBillId!);
      } else if (widget.tableId != null) {
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
      } else {
        result = await createBill({
          'items': _cartPayload,
          if (_customerNameController.text.trim().isNotEmpty)
            'customer_name': _customerNameController.text.trim(),
          if (_customerPhoneController.text.trim().isNotEmpty)
            'customer_phone': _customerPhoneController.text.trim(),
          'payment_mode': _paymentMode,
          'status': 'finalized',
        });
      }

      final bill = Bill.fromJson(result);
      if (!mounted) return;

      ref.read(cartProvider.notifier).clear();
      _customerNameController.clear();
      _customerPhoneController.clear();
      setState(() => _paymentMode = 'cash');

      // Invalidate report so it refreshes next time reports tab opens
      ref.invalidate(reportProvider);

      _showBillDialog(bill);
      _autoPrint(bill);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Failed to generate bill. Check your connection.', isError: true);
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
      final total =
          double.parse((subtotal + taxAmount).toStringAsFixed(2));

      final localId = await OfflineService.instance.queueOfflineBill({
        'business_id': businessId,
        'user_id': userId,
        'table_id': widget.tableId,
        'customer_name':
            _customerNameController.text.trim().nullIfEmpty,
        'customer_phone':
            _customerPhoneController.text.trim().nullIfEmpty,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'total': total,
        'payment_mode': _paymentMode,
        'items_json': jsonEncode(lineItems),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Build a local Bill object for the receipt dialog
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
      ref.invalidate(pendingSyncCountProvider);

      if (!mounted) return;
      _showBillDialog(fakeBill);
      _autoPrint(fakeBill);
    } catch (e) {
      _showSnack('Failed to save bill offline: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generatingBill = false);
    }
  }

  Future<void> _triggerSync() async {
    final result = await SyncService.instance.syncAll();
    ref.invalidate(pendingSyncCountProvider);
    if (!mounted) return;
    final msg = result.failed > 0
        ? 'Synced ${result.synced}, failed ${result.failed}'
        : 'Synced ${result.synced} bill${result.synced == 1 ? '' : 's'}';
    _showSnack(msg, isError: result.failed > 0);
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
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.accent),
            const SizedBox(width: AppSpacing.space8),
            Text('Bill ${bill.billNumber}'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...bill.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(
                                '${item.itemName} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)}',
                                style: Theme.of(context).textTheme.bodyMedium)),
                        Text('₹${item.lineTotal.toStringAsFixed(2)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
              const Divider(height: AppSpacing.space24),
              if (bill.taxAmount > 0) ...[
                _billRow('Subtotal', '₹${bill.subtotal.toStringAsFixed(2)}'),
                _billRow('Tax', '₹${bill.taxAmount.toStringAsFixed(2)}'),
              ],
              _billRow('Total', '₹${bill.total.toStringAsFixed(2)}', bold: true),
              const SizedBox(height: AppSpacing.space8),
              _billRow('Payment', bill.paymentMode.toUpperCase()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.tableId != null) Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _autoPrint(bill);
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
          ),
        ],
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary))),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: bold ? AppColors.textPrimary : null,
                  )),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : null,
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final businessName = ref.watch(businessNameProvider);
    final userName = ref.watch(userNameProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: _buildAppBar(businessName, userName),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
      floatingActionButton: null,
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
            Text('Table ${widget.tableNumber}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.primary)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.space8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(userName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(width: AppSpacing.space8),
              IconButton(
                icon: const Icon(Icons.logout_outlined, size: 20),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------------

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: _buildItemsPanel()),
        const VerticalDivider(width: 1),
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
            child: FloatingActionButton.extended(
              onPressed: _openCartSheet,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: Text(count == 0 ? 'Cart' : 'Cart ($count)'),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
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

  Widget _buildOfflineBanner() {
    return Consumer(builder: (context, ref, _) {
      final isOnline = ref.watch(connectivityProvider);
      final pendingAsync = ref.watch(pendingSyncCountProvider);
      final pending = pendingAsync.valueOrNull ?? 0;

      if (isOnline && pending == 0) return const SizedBox.shrink();

      final color = isOnline ? Colors.orange.shade700 : AppColors.error;
      final icon = isOnline ? Icons.sync_outlined : Icons.wifi_off_outlined;
      final message = isOnline
          ? '$pending bill${pending == 1 ? '' : 's'} pending sync'
          : pending > 0
              ? 'Offline — $pending bill${pending == 1 ? '' : 's'} pending sync'
              : 'Offline — using cached items';

      return Container(
        color: color,
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.space16, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: AppSpacing.space8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            if (isOnline && pending > 0)
              TextButton(
                onPressed: _triggerSync,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Sync now',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildItemsPanel() {
    return Column(
      children: [
        _buildOfflineBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.space16, AppSpacing.space16, AppSpacing.space16, AppSpacing.space8),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search items…',
              prefixIcon: Icon(Icons.search_outlined, size: 20),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: AppSpacing.space16, vertical: 12),
            ),
          ),
        ),
        // Category chips
        Consumer(builder: (context, ref, _) {
          final cats = ref.watch(categoriesProvider).valueOrNull ?? [];
          if (cats.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space16),
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.space8),
              itemBuilder: (_, i) {
                final cat = cats[i];
                final selected = _selectedCategory == cat;
                return FilterChip(
                  label: Text(cat),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _selectedCategory = _selectedCategory == cat ? '' : cat;
                  }),
                  backgroundColor: AppColors.surface,
                  selectedColor: AppColors.primaryLight,
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small)),
                );
              },
            ),
          );
        }),
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
        error: (e, _) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(itemsProvider);
            await ref.read(itemsProvider.future);
          },
          child: ListView(children: [
            EmptyState(
              icon: Icons.wifi_off_outlined,
              message: e.toString(),
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(itemsProvider),
            ),
          ]),
        ),
        data: (allItems) {
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
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space8, AppSpacing.space4, AppSpacing.space8, 80),
              itemCount: items.length,
              itemBuilder: (_, i) => _buildItemRow(items[i], cart),
            ),
          );
        },
      );
    });
  }

  Widget _buildItemRow(Item item, List<CartEntry> cart) {
    final entry = cart.where((e) => e.item.id == item.id).firstOrNull;
    final qty = entry?.quantity ?? 0;
    final inCart = qty > 0;

    return InkWell(
      onTap: inCart ? null : () => ref.read(cartProvider.notifier).addItem(item),
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: inCart ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(
            color: inCart ? AppColors.primary : AppColors.border,
            width: inCart ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Name + category
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: inCart ? AppColors.primaryDark : AppColors.textPrimary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.category != null)
                    Text(
                      item.category!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textDisabled),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Price
            Text(
              '₹${item.price.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: inCart ? AppColors.primary : AppColors.textSecondary,
                  ),
            ),
            const SizedBox(width: AppSpacing.space8),
            // Qty controls or add button
            if (inCart)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _cardQtyButton(Icons.remove,
                      () => ref.read(cartProvider.notifier).changeQty(item.id, -1)),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                  ),
                  _cardQtyButton(Icons.add,
                      () => ref.read(cartProvider.notifier).addItem(item)),
                ],
              )
            else
              _cardQtyButton(Icons.add,
                  () => ref.read(cartProvider.notifier).addItem(item)),
          ],
        ),
      ),
    );
  }

  Widget _cardQtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    );
  }

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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space16, AppSpacing.space16, AppSpacing.space16, AppSpacing.space8),
              child: Text('Order', style: Theme.of(context).textTheme.titleLarge),
            ),
            if (cart.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.space32, horizontal: AppSpacing.space16),
                child: Column(
                  children: [
                    const Icon(Icons.shopping_cart_outlined,
                        size: 40, color: AppColors.textDisabled),
                    const SizedBox(height: AppSpacing.space8),
                    Text('No items added yet',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            else
              ...cart.asMap().entries.map((entry) {
                final e = entry.value;
                return _buildCartRow(e);
              }),

            if (cart.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space16),
                child: Column(
                  children: [
                    if (tax > 0) ...[
                      _totalRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                      _totalRow('Tax', '₹${tax.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                    ],
                    _totalRow('Total', '₹${total.toStringAsFixed(2)}', bold: true),
                  ],
                ),
              ),
            ],

            const Divider(height: 1),

            // Customer info toggle
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
              child: Row(
                children: [
                  Text('Customer details (optional)',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                        _showCustomerFields
                            ? Icons.keyboard_arrow_up_outlined
                            : Icons.keyboard_arrow_down_outlined,
                        size: 20),
                    onPressed: () =>
                        setState(() => _showCustomerFields = !_showCustomerFields),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            if (_showCustomerFields) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space8),
                child: Column(
                  children: [
                    AppTextField(
                      label: 'Customer name',
                      controller: _customerNameController,
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    AppTextField(
                      label: 'Customer phone',
                      controller: _customerPhoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                    ),
                  ],
                ),
              ),
            ],

            // Payment mode
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space16),
              child: DropdownButtonFormField<String>(
                initialValue: _paymentMode,
                decoration: const InputDecoration(labelText: 'Payment mode'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'credit', child: Text('Credit')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _paymentMode = v!),
              ),
            ),

            if (widget.tableId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space8),
                child: SecondaryButton(
                  text: _savingDraft ? 'Saving…' : 'Save Draft',
                  onPressed: (cart.isEmpty || _savingDraft) ? null : _saveDraft,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space16),
              child: PrimaryButton(
                text: 'Generate Bill',
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
          horizontal: AppSpacing.space16, vertical: AppSpacing.space4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.item.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('₹${entry.lineTotal.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ),
          ),
          Row(
            children: [
              _qtyButton(Icons.remove,
                  () => ref.read(cartProvider.notifier).changeQty(entry.item.id, -1)),
              SizedBox(
                width: 32,
                child: Text('${entry.quantity}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              _qtyButton(Icons.add,
                  () => ref.read(cartProvider.notifier).changeQty(entry.item.id, 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: bold ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                    ))),
        Text(value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                )),
      ],
    );
  }
}
