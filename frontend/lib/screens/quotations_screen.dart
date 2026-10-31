import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/file_export.dart';
import '../services/receipt_labels.dart';
import '../services/receipt_output.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/skeletons.dart';
import 'home_screen.dart';

/// The Orders page's Quotations tab: every open quote, newest first. Each can
/// be converted (opens billing with its cart; settling it bills it and drops
/// it from here), printed, shared as a PDF (WhatsApp via the share sheet), or
/// deleted. Tapping a card opens it to edit — Quote there saves the changes.
class QuotationsScreen extends ConsumerStatefulWidget {
  /// Search text from the Orders page header; empty shows every quotation.
  final String query;

  const QuotationsScreen({super.key, this.query = ''});

  @override
  ConsumerState<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends ConsumerState<QuotationsScreen> {
  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : null,
      ));

  void _open(Quotation q) {
    // Start from a clean cart; HomeScreen loads the quote's items itself.
    ref.read(cartProvider.notifier).clear();
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => HomeScreen(quotation: q, openCart: true)),
    ).then((_) {
      // Back from billing: drop the borrowed cart so the quote's items never
      // leak into a fresh order, and re-read the list (it may be converted).
      ref.read(cartProvider.notifier).clear();
      ref.read(quotationsProvider.notifier).reload();
    });
  }

  /// The shop details every printout carries — same as billing's _autoPrint.
  Future<
      ({
        String name,
        String? address,
        String? phone,
        String? gstin,
        String? fssai,
        String? sac,
        bool gst,
      })> _business() async {
    final p = await getGstProfile();
    String? v(String k) => (p[k] ?? '').isEmpty ? null : p[k];
    final gst = ref.read(gstEnabledProvider);
    return (
      name: ref.read(businessNameProvider),
      address: v('business_address'),
      phone: v('business_phone'),
      gstin: gst ? v('gst_number') : null,
      fssai: v('fssai_number'),
      sac: v('default_sac_code'),
      gst: gst,
    );
  }

  Future<void> _print(Quotation q) async {
    final l10n = context.l10n;
    final labels = ReceiptLabels.from(l10n, ref.read(localeProvider).code);
    try {
      final b = await _business();
      await ReceiptOutput.emit([q.bill],
          businessName: b.name,
          businessAddress: b.address,
          businessPhone: b.phone,
          businessGstin: b.gstin,
          businessFssai: b.fssai,
          defaultSacCode: b.sac,
          gstEnabled: b.gst,
          labels: labels);
    } catch (e) {
      if (mounted) _snack(l10n.billingPrintFailed('$e'), isError: true);
    }
  }

  /// An A4 PDF through the share sheet — WhatsApp, email, anything.
  Future<void> _share(Quotation q) async {
    final l10n = context.l10n;
    try {
      final b = await _business();
      final bytes = await ReceiptOutput.pdf([q.bill],
          pageFormat: PdfPageFormat.a4,
          businessName: b.name,
          businessAddress: b.address,
          businessPhone: b.phone,
          businessGstin: b.gstin,
          businessFssai: b.fssai,
          defaultSacCode: b.sac,
          gstEnabled: b.gst);
      await shareFile(bytes, 'Quotation-${q.number}.pdf', 'application/pdf',
          text: l10n.quotationShareText(q.number, b.name));
    } catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
    }
  }

  Future<void> _delete(Quotation q) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.quotationDeleteConfirm(q.number)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.commonDelete,
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteQuotation(q.id);
      await ref.read(quotationsProvider.notifier).reload();
    } catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ref.watch(quotationsProvider).when(
          loading: () => const OrdersListSkeleton(),
          error: (e, _) => AppErrorWidget(
            error: e,
            onRetry: () => ref.invalidate(quotationsProvider),
          ),
          data: (all) {
            final q = widget.query.trim().toLowerCase();
            final shown = q.isEmpty
                ? all
                : all
                    .where((x) => [
                          x.number,
                          x.bill.customerName,
                          x.bill.customerPhone,
                        ].whereType<String>().join(' ').toLowerCase().contains(q))
                    .toList();
            return RefreshIndicator(
              onRefresh: () => ref.read(quotationsProvider.notifier).reload(),
              child: shown.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.request_quote_outlined,
                          size: 48, color: AppColors.textDisabled),
                      const SizedBox(height: AppSpacing.space16),
                      Text(
                        all.isEmpty ? l10n.quotationsEmpty : l10n.openOrdersNoMatches,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ])
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                          AppSpacing.space16,
                          AppSpacing.space12,
                          AppSpacing.space16,
                          AppSpacing.space16 +
                              MediaQuery.paddingOf(context).bottom),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.space12),
                      itemBuilder: (_, i) => _QuotationCard(
                        quotation: shown[i],
                        onOpen: () => _open(shown[i]),
                        onPrint: () => _print(shown[i]),
                        onShare: () => _share(shown[i]),
                        onDelete: () => _delete(shown[i]),
                      ),
                    ),
            );
          },
        );
  }
}

class _QuotationCard extends StatelessWidget {
  final Quotation quotation;
  final VoidCallback onOpen;
  final VoidCallback onPrint;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _QuotationCard({
    required this.quotation,
    required this.onOpen,
    required this.onPrint,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final bill = quotation.bill;
    final who = [bill.customerName, bill.customerPhone]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
              AppSpacing.space12, AppSpacing.space8, AppSpacing.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(quotation.number,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.info, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: AppSpacing.space8),
                Expanded(
                  child: Text(
                    DateFormat('d MMM, h:mm a')
                        .format(quotation.createdAt.toLocal()),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                Text('₹${quotation.total.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: AppSpacing.space8),
              ]),
              const SizedBox(height: AppSpacing.space8),
              if (who.isNotEmpty)
                Text(who,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              Text(
                l10n.quotationItemCount(bill.items.length),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space4),
              Row(children: [
                IconButton(
                  tooltip: l10n.commonDelete,
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                  onPressed: onDelete,
                ),
                IconButton(
                  tooltip: l10n.quotationPrint,
                  icon: const Icon(Icons.print_outlined, size: 20),
                  onPressed: onPrint,
                ),
                IconButton(
                  tooltip: l10n.quotationShare,
                  icon: const Icon(Icons.share_outlined, size: 20),
                  onPressed: onShare,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(l10n.quotationConvert),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
