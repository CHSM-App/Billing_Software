import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart' show ApiException, sanitizeUiErrorMessage;
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

/// The shop's queue of orders placed on the public store link.
///
/// Every card is a decision: accept (which creates the draft bill and sends the
/// items to the kitchen) or decline with a reason. Nothing here edits an order —
/// once accepted it is an ordinary draft bill and the billing screen owns it.
class OnlineOrdersScreen extends ConsumerWidget {
  /// When embedded in the shell's tab view the shell supplies the app bar.
  final bool embedded;

  const OnlineOrdersScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final body = _OnlineOrdersBody();
    if (embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: Text(l10n.onlineOrdersTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => ref.invalidate(onlineOrdersProvider),
              tooltip: l10n.commonRefresh,
            ),
          ],
        ),
        Expanded(child: body),
      ]),
    );
  }
}

class _OnlineOrdersBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(onlineOrdersProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(
        error: e,
        onRetry: () => ref.read(onlineOrdersProvider.notifier).reload(),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => ref.read(onlineOrdersProvider.notifier).reload(),
            // A scrollable is required for pull-to-refresh to work on an
            // otherwise empty page.
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                EmptyState(
                  icon: Icons.storefront_outlined,
                  message: '${l10n.onlineOrdersEmpty}\n${l10n.onlineOrdersEmptyHint}',
                ),
              ],
            ),
          );
        }

        // Three groups, because an accepted order is not a finished one: its
        // bill is still open at the counter. Filing it under "decided" would
        // read as done while the customer is still waiting for their food.
        final pending = orders.where((o) => o.isPending).toList();
        final inProgress =
            orders.where((o) => !o.isPending && o.isOpen).toList();
        final done = orders.where((o) => !o.isOpen).toList();

        return RefreshIndicator(
          onRefresh: () => ref.read(onlineOrdersProvider.notifier).reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.space16),
            children: [
              if (pending.isNotEmpty) ...[
                _sectionLabel(context, '${l10n.onlineOrdersWaiting} (${pending.length})'),
                for (final o in pending) _OnlineOrderCard(order: o),
              ],
              if (inProgress.isNotEmpty) ...[
                if (pending.isNotEmpty) const SizedBox(height: AppSpacing.space16),
                _sectionLabel(context, l10n.onlineOrdersInProgress),
                for (final o in inProgress) _OnlineOrderCard(order: o),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.space16),
                _sectionLabel(context, l10n.onlineOrdersDecided),
                for (final o in done) _OnlineOrderCard(order: o),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space8, left: AppSpacing.space4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

class _OnlineOrderCard extends ConsumerStatefulWidget {
  final OnlineOrder order;
  const _OnlineOrderCard({required this.order});

  @override
  ConsumerState<_OnlineOrderCard> createState() => _OnlineOrderCardState();
}

class _OnlineOrderCardState extends ConsumerState<_OnlineOrderCard> {
  bool _busy = false;

  /// Ticked by the owner when they have seen the customer's payment land in
  /// their own UPI app. Nothing server-side can confirm a typed reference, so
  /// this checkbox is the only thing that promotes 'claimed' to 'verified'.
  bool _paymentSeen = false;

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  Future<void> _accept() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final billNumber = await ref
          .read(onlineOrdersProvider.notifier)
          .accept(widget.order.id, paymentVerified: _paymentSeen);
      if (!mounted) return;
      // Accepting also creates a draft bill, so the Open Orders queue must
      // catch up or the new bill is invisible until the next event.
      ref.read(openDraftsProvider.notifier).refreshSilently();
      _snack(l10n.onlineOrderAccepted(billNumber ?? ''));
    } on ApiException catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
      // A 409 means another device decided it — pull the truth back in.
      ref.read(onlineOrdersProvider.notifier).refreshSilently();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.onlineOrderRejectTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.onlineOrderRejectHint,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.space16),
            TextField(
              controller: controller,
              maxLength: 200,
              decoration: InputDecoration(labelText: l10n.onlineOrderRejectReason),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.onlineOrderReject,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(onlineOrdersProvider.notifier)
          .reject(widget.order.id, controller.text.trim());
      if (mounted) _snack(l10n.onlineOrderRejected);
    } on ApiException catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
      ref.read(onlineOrdersProvider.notifier).refreshSilently();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final o = widget.order;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space8),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space12, vertical: AppSpacing.space12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(
          color: o.isPending ? AppColors.warning : AppColors.border,
          width: o.isPending ? 1.5 : 1,
        ),
        boxShadow: AppShadow.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1 — order number, how it leaves the shop, where it stands.
          Row(
            children: [
              Text(o.orderNumber,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(width: 6),
              _chip(
                o.isDelivery ? Icons.delivery_dining : Icons.storefront_outlined,
                o.isDelivery ? l10n.onlineOrderDelivery : l10n.onlineOrderPickup,
              ),
              const Spacer(),
              _statusBadge(l10n, o),
            ],
          ),
          const SizedBox(height: 2),

          // Line 2 — who. Name and number on one line; they are one fact.
          Text(
            [o.customerName, o.customerPhone].where((s) => (s ?? '').isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),

          // Address and note: icon + text, no label row above them. The pin
          // icon already says "address" in less space than the word does.
          if (o.isDelivery && (o.address?.isNotEmpty ?? false))
            _iconLine(Icons.location_on_outlined, o.address!),
          if (o.note?.isNotEmpty ?? false)
            _iconLine(Icons.sticky_note_2_outlined, o.note!, italic: true),

          const Divider(height: AppSpacing.space16),

          // What was ordered. Tight rows — a five-line order should not need
          // scrolling to see the buttons under it.
          for (final i in o.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_qty(i.quantity)} × ${i.itemName}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(_money(i.lineTotal),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),

          const SizedBox(height: 4),
          // Delivery fee folded into the total line rather than given its own
          // row — it is a detail of the total, not a second thing to read.
          Row(
            children: [
              Expanded(
                child: Text(
                  o.deliveryCharge > 0
                      ? '${l10n.onlineOrderTotal}  (+${_money(o.deliveryCharge)} ${l10n.onlineOrderDeliveryFee.toLowerCase()})'
                      : l10n.onlineOrderTotal,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(_money(o.total),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),

          _paymentBlock(l10n, o),

          if (o.isPending) ...[
            const SizedBox(height: AppSpacing.space12),
            // 40px buttons instead of the 52px shared ones: this card repeats
            // down a list, so every pixel of chrome is paid for many times.
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _reject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.border),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(l10n.onlineOrderReject,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _busy ? null : _accept,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(l10n.onlineOrderAccept,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (o.billNumber != null)
            _iconLine(Icons.receipt_long_outlined, o.billNumber!)
          else if (o.rejectReason?.isNotEmpty ?? false)
            _iconLine(Icons.block, o.rejectReason!, color: AppColors.error),
        ],
      ),
    );
  }

  /// One compact fact: a small icon and its text, wrapping if long.
  Widget _iconLine(IconData icon, String text,
          {Color color = AppColors.textSecondary, bool italic = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      );

  /// Payment is the part an owner must not skim: whether money was claimed, how
  /// much, and the reference to look up. Absent entirely when the shop asks for
  /// no advance, so a pickup-and-pay shop sees no payment clutter at all.
  Widget _paymentBlock(AppLocalizations l10n, OnlineOrder o) {
    if (o.amountDue <= 0 && o.paidAmount <= 0) return const SizedBox.shrink();

    final paid = o.paidAmount > 0;
    final hasTxn = o.paymentTxnId?.isNotEmpty ?? false;
    // Settled online in full, so nothing is owed at the counter. This — not
    // "did they pay something" — is what decides the colour, because the one
    // thing an owner scans this block for is whether money is still to collect.
    final settled = paid && o.paidAmount >= o.total;
    final balance = o.total - o.paidAmount;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.space8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: settled ? AppColors.successLight : AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The money summary owns its own line and is free to wrap.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(settled ? Icons.check_circle_outline : Icons.schedule,
                  size: 15, color: settled ? AppColors.success : AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !paid
                      ? '${l10n.onlineOrderUnpaid} (${_money(o.amountDue)})'
                      : settled
                          ? '${l10n.onlineOrderPaidFull} ${_money(o.paidAmount)}'
                          // Part-paid: show BOTH halves, or the counter has to
                          // do the subtraction while a customer waits.
                          : '${l10n.onlineOrderPaidOnline} ${_money(o.paidAmount)}'
                              '  ·  ${l10n.onlineOrderBalanceDue(_money(balance))}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          // The reference gets a FULL line of its own. Sharing a row with the
          // amount squeezed it to a few characters — and this is the one string
          // the owner has to match character-for-character in their UPI app, so
          // a truncated one is worse than none. Tap to copy rather than retype.
          if (hasTxn)
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: o.paymentTxnId!));
                if (context.mounted) _snack(l10n.onlineOrderTxnCopied);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: '${l10n.onlineOrderTxnId}: ',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                          TextSpan(
                            text: o.paymentTxnId!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ]),
                        // No maxLines: a long reference wraps rather than
                        // losing its tail.
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded,
                        size: 14, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          // The confirmation tap only appears while the decision is still open
          // and there is actually a claim to confirm. A whole CheckboxListTile
          // for this wasted a row of height, so it is a compact tap target.
          if (o.isPending && hasTxn)
            InkWell(
              onTap: _busy ? null : () => setState(() => _paymentSeen = !_paymentSeen),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: _paymentSeen,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _paymentSeen = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.onlineOrderPaymentReceived,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(AppLocalizations l10n, OnlineOrder o) {
    final (label, type) = switch (o.status) {
      'accepted' => (l10n.onlineOrderStatusAccepted, StatusType.success),
      'rejected' => (l10n.onlineOrderStatusRejected, StatusType.error),
      _ => (l10n.onlineOrderStatusPending, StatusType.warning),
    };
    return StatusBadge(label: label, status: type);
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
        ),
      );

  /// Quantities are stored as decimals but are almost always whole — show 2 not
  /// 2.00, while still showing 1.5 for a weighed item.
  String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
