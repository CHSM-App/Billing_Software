import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../providers/credit_provider.dart';
import '../services/printer_service.dart';
import '../services/receipt_output.dart';
import '../services/receipt_labels.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

/// Shows one credit customer's unpaid bills. The cashier/owner selects one or
/// more, then settles them (marks paid with a payment mode), prints a merged
/// receipt, or sends the receipt links over WhatsApp.
class CreditCustomerBillsScreen extends ConsumerStatefulWidget {
  final CreditCustomer customer;

  const CreditCustomerBillsScreen({super.key, required this.customer});

  @override
  ConsumerState<CreditCustomerBillsScreen> createState() =>
      _CreditCustomerBillsScreenState();
}

class _CreditCustomerBillsScreenState
    extends ConsumerState<CreditCustomerBillsScreen> {
  final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  List<Bill> _bills = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await getCreditCustomerBills(widget.customer.customerPhone);
      final bills = data.map((j) => Bill.fromJson(j)).toList();
      if (!mounted) return;
      setState(() {
        _bills = bills;
        // Drop selections for bills no longer present.
        _selected.retainWhere((id) => bills.any((b) => b.id == id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  double get _selectedTotal => _bills
      .where((b) => _selected.contains(b.id))
      .fold(0.0, (s, b) => s + b.grandTotal);

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _bills.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_bills.map((b) => b.id));
      }
    });
  }

  List<Bill> get _selectedBills =>
      _bills.where((b) => _selected.contains(b.id)).toList();

  // ── Settlement sheet ────────────────────────────────────────────────────────

  /// Opens the settlement sheet — the credit equivalent of the billing-page
  /// checkout. It lists the merged (read-only) items and total, lets the user
  /// pick the payment mode, then settle with an optional Print / WhatsApp.
  Future<void> _openSettlementSheet() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _showSnack(l10n.creditSelectAtLeastOne, isError: true);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SettlementSheet(
        bills: _selectedBills,
        onConfirm: (mode, action) => _confirmSettlement(mode, action),
      ),
    );
  }

  /// Settles the selected bills with [mode], then performs [action]
  /// (print / whatsapp / none). Closes the sheet and this screen on success.
  Future<void> _confirmSettlement(String mode, _SettleAction action) async {
    final l10n = context.l10n;
    // Snapshot before settling — the merged receipt is built from these.
    final bills = _selectedBills;

    setState(() => _busy = true);
    try {
      await settleCreditBills(bills.map((b) => b.id).toList(), mode);
      if (!mounted) return;

      // Fulfil the chosen delivery, best-effort — settlement already succeeded.
      if (action == _SettleAction.print) {
        await _printEach(bills, mode);
      } else if (action == _SettleAction.whatsapp) {
        await _sendWhatsAppFor(bills);
      }
      if (!mounted) return;

      _showSnack(l10n.creditSettledSuccess);
      ref.read(creditCustomersProvider.notifier).refreshSilently();
      Navigator.pop(context); // close the sheet
      if (mounted) Navigator.pop(context); // leave this customer
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } catch (_) {
      if (mounted) _showSnack(l10n.creditSettleFailed, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Print (one receipt per bill) ────────────────────────────────────────────

  /// Prints each settled bill as its OWN receipt — bills are never merged.
  /// One tap prints all selected bills in sequence. [settledMode] is how the
  /// credit was actually paid, so each receipt shows e.g. "Cash", not "Credit".
  Future<void> _printEach(List<Bill> bills, String settledMode) async {
    final l10n = context.l10n;
    if (bills.isEmpty) {
      _showSnack(l10n.creditSelectAtLeastOne, isError: true);
      return;
    }
    // PDF sizes (A5/A4) open the OS print dialog and need no thermal printer;
    // only require a paired printer for the thermal sizes.
    final pdfSelected = await ReceiptOutput.isPdfSelected();
    if (!pdfSelected) {
      final printer = await PrinterService.instance.getActivePrinter();
      if (printer == null) {
        if (mounted) _showSnack(l10n.historyNoPrinterConfigured, isError: true);
        return;
      }
    }
    final businessName = ref.read(businessNameProvider);
    final labels = ReceiptLabels.from(l10n, ref.read(localeProvider).code);
    // Address + FSSAI print whenever available; GSTIN only when GST is enabled
    // (else gstin stays null → non-GST receipt is byte-for-byte as before).
    final profile = await getGstProfile();
    final addr = profile['business_address'] ?? '';
    final fss = profile['fssai_number'] ?? '';
    final sac = profile['default_sac_code'] ?? '';
    final gstEnabled = ref.read(gstEnabledProvider);
    final String? address = addr.isNotEmpty ? addr : null;
    final String? fssai = fss.isNotEmpty ? fss : null;
    String? gstin;
    if (gstEnabled) {
      final g = profile['gst_number'] ?? '';
      gstin = g.isNotEmpty ? g : null;
    }
    try {
      // Each settled bill prints as its own receipt (never merged). For thermal
      // the service settles the BT link between jobs; for PDF each bill is a page.
      final printables =
          bills.map((b) => _asSettled(b, settledMode)).toList();
      await ReceiptOutput.emit(printables,
          businessName: businessName,
          businessAddress: address,
          businessGstin: gstin,
          businessFssai: fssai,
          defaultSacCode: sac.isNotEmpty ? sac : null,
          gstEnabled: gstEnabled,
          labels: labels);
      if (mounted) _showSnack(l10n.billingPrintSuccess);
    } on PrinterException catch (e) {
      if (e.message == 'No printer configured') return;
      if (mounted) _showSnack(l10n.billingPrintFailed(e.message), isError: true);
    } catch (e) {
      if (mounted) _showSnack(l10n.billingPrintFailed('$e'), isError: true);
    }
  }

  /// Copy of [bill] with the settled payment mode set, so the printed receipt
  /// shows the real collection method instead of "Credit". Nothing is merged.
  Bill _asSettled(Bill bill, String settledMode) => Bill(
        id: bill.id,
        businessId: bill.businessId,
        billNumber: bill.billNumber,
        customerName: bill.customerName ?? widget.customer.customerName,
        customerPhone: bill.customerPhone ?? widget.customer.customerPhone,
        subtotal: bill.subtotal,
        taxAmount: bill.taxAmount,
        discountAmount: bill.discountAmount,
        total: bill.total,
        roundOff: bill.roundOff,
        paymentMode: settledMode,
        status: 'finalized',
        paymentStatus: 'paid',
        createdByUserId: bill.createdByUserId,
        createdAt: bill.createdAt,
        items: bill.items,
      );

  // ── WhatsApp ────────────────────────────────────────────────────────────────

  Future<void> _sendWhatsAppFor(List<Bill> bills) async {
    final l10n = context.l10n;
    try {
      // Per bill (never merged). The backend decides API vs deeplink per its
      // whatsapp_mode: 'api' sends server-side; 'deeplink' returns phone +
      // message and we open the cashier's WhatsApp in sequence.
      for (var i = 0; i < bills.length; i++) {
        if (i > 0) await Future.delayed(const Duration(milliseconds: 300));
        final data = await whatsAppBill(bills[i].id);
        if (data['mode'] == 'api') {
          continue; // sent server-side; nothing to open
        }
        final phone = (data['phone'] ?? '').toString();
        final message = (data['message'] ?? '').toString();
        if (phone.isEmpty) continue;
        final text = Uri.encodeComponent(message);
        // Try whatsapp:// first (most reliable when installed), then wa.me.
        for (final uri in [
          Uri.parse('whatsapp://send?phone=$phone&text=$text'),
          Uri.parse('https://wa.me/$phone?text=$text'),
        ]) {
          try {
            if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              break;
            }
          } catch (_) {
            // try next candidate
          }
        }
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

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = (widget.customer.customerName != null &&
            widget.customer.customerName!.trim().isNotEmpty)
        ? widget.customer.customerName!.trim()
        : widget.customer.customerPhone;
    final allSelected =
        _bills.isNotEmpty && _selected.length == _bills.length;

    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          title: Text(name),
          actions: [
            if (_bills.isNotEmpty)
              TextButton(
                onPressed: _toggleAll,
                child: Text(allSelected ? l10n.commonClear : l10n.creditSelectAll),
              ),
          ],
        ),
        Expanded(child: _buildBody(l10n)),
        if (_bills.isNotEmpty) _buildActionBar(l10n),
      ]),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppErrorWidget(error: _error!, onRetry: _load);
    }
    if (_bills.isEmpty) {
      return Center(
        child: Text(l10n.creditEmpty,
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.space12),
      itemCount: _bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
      itemBuilder: (context, i) {
        final bill = _bills[i];
        final selected = _selected.contains(bill.id);
        final itemCount = bill.items.fold<double>(0, (s, it) => s + it.quantity);
        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            side: BorderSide(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: () => _toggle(bill.id),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space12),
              child: Row(
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (_) => _toggle(bill.id),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bill.billNumber,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${_dateFmt.format(bill.createdAt.toLocal())} · ${l10n.openOrdersItemCount(itemCount.toInt())}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${bill.grandTotal.toStringAsFixed(2)}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionBar(AppLocalizations l10n) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.creditSelectedTotal(_selectedTotal.toStringAsFixed(2)),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: AppSpacing.space8),
              // Single action: open the settlement sheet (payment mode +
              // Print / WhatsApp), mirroring the billing-page checkout.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      (_busy || _selected.isEmpty) ? null : _openSettlementSheet,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(l10n.creditMarkPaid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.space12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which delivery to perform after settling. Both settle the bills; they only
/// differ in how the receipt is delivered.
enum _SettleAction { print, whatsapp }

/// The settlement sheet — the credit equivalent of the billing checkout.
/// Shows the merged items (read-only), the total and a payment-mode selector,
/// then settles via Print / WhatsApp / plain Confirm. Items are NOT editable.
class _SettlementSheet extends StatefulWidget {
  final List<Bill> bills;
  final Future<void> Function(String mode, _SettleAction action) onConfirm;

  const _SettlementSheet({required this.bills, required this.onConfirm});

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  String _mode = 'cash';
  bool _busy = false;
  final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  double get _total => widget.bills
      .fold(0.0, (s, b) => s + b.grandTotal);

  Future<void> _run(_SettleAction action) async {
    setState(() => _busy = true);
    try {
      await widget.onConfirm(_mode, action);
    } finally {
      // The parent closes this sheet on success; if it's still mounted the
      // settlement failed, so re-enable the buttons.
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One bill in the read-only summary: bill number + date heading, then its
  /// items listed below.
  Widget _buildBillGroup(Bill bill) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space12, vertical: AppSpacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading: bill number + date
          Row(
            children: [
              Expanded(
                child: Text(bill.billNumber,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text(_dateFmt.format(bill.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          // Items
          ...bill.items.map((it) {
            final qty = it.quantity.toStringAsFixed(
                it.quantity == it.quantity.roundToDouble() ? 0 : 2);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${it.itemName}  ×$qty',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
                  Text('₹${it.lineTotal.toStringAsFixed(2)}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.space16,
          right: AppSpacing.space16,
          top: AppSpacing.space12,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.space12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(l10n.creditMarkPaid,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.space12),

            // Read-only bills, grouped by bill. Each bill shows its number +
            // date as a heading, with its items listed below. Scrolls if long.
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space4),
                  itemCount: widget.bills.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, thickness: 1),
                  itemBuilder: (_, i) => _buildBillGroup(widget.bills[i]),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space12),

            // Total
            Row(
              children: [
                Text(l10n.billingNetPayable,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('₹${_total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: AppSpacing.space12),

            // Payment mode selector (how the credit is being paid now).
            DropdownButtonFormField<String>(
              value: _mode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.creditChoosePaymentMode,
                prefixIcon: const Icon(Icons.payments_outlined,
                    size: 18, color: AppColors.textSecondary),
              ),
              items: [
                DropdownMenuItem(value: 'cash', child: Text(l10n.paymentCash)),
                DropdownMenuItem(value: 'upi', child: Text(l10n.paymentUpi)),
                DropdownMenuItem(value: 'card', child: Text(l10n.paymentCard)),
                DropdownMenuItem(value: 'other', child: Text(l10n.paymentOther)),
              ],
              onChanged:
                  _busy ? null : (v) => setState(() => _mode = v ?? 'cash'),
            ),
            const SizedBox(height: AppSpacing.space16),

            // Deliver: WhatsApp / Print — each settles then delivers.
            // Print and WhatsApp — each marks the bills paid AND delivers the
            // receipt. There's no separate "mark paid": choosing either settles.
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.space12),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _run(_SettleAction.whatsapp),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: Text(l10n.creditSendWhatsapp),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space12),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _run(_SettleAction.print),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(l10n.creditPrint),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.space12),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
