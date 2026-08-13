import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../l10n/l10n_ext.dart';
import '../services/receipt_output.dart';
import '../theme/app_theme.dart';
import '../widgets/shell_app_bar.dart';

/// Full-screen, read-only preview of a bill exactly as it will be printed:
/// a thermal receipt bitmap (58/80mm) shown on a paper-like card, or an A5/A4
/// PDF invoice shown in a scrollable PDF viewer. Nothing here saves or prints —
/// it's a look-before-you-commit view opened from the billing card.
class BillPreviewScreen extends StatelessWidget {
  final ReceiptPreview preview;

  const BillPreviewScreen({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ShellAppBar(
            title: Text(l10n.billingPreviewTitle),
          ),
          Expanded(
            child: preview.isPdf ? _pdfView() : _receiptView(),
          ),
        ],
      ),
    );
  }

  /// A4/A5 invoice — the printing package's viewer renders the PDF faithfully
  /// (multi-page, zoom, scroll) without exposing the print/share actions, since
  /// this is preview-only.
  Widget _pdfView() => PdfPreview(
        build: (_) async => preview.bytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
      );

  /// Thermal receipt bitmap — shown at a comfortable width on a white "paper"
  /// card against a muted backdrop, zoomable for the fine print. The image is a
  /// 1-bit render, so it's crisp when scaled up.
  Widget _receiptView() => Container(
        color: AppColors.background,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.small),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(
                  preview.bytes,
                  fit: BoxFit.fitWidth,
                  // The preview is a high-res anti-aliased render; smooth it when
                  // scaling so it stays crisp instead of pixelated.
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      );
}
