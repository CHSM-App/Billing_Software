import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../services/file_export.dart';
import '../theme/app_theme.dart';

enum ExportFormat { excel, pdf }

enum ExportAction { download, share }

/// Two quick sheets: Excel or PDF, then Download or Share. Null if dismissed.
Future<(ExportFormat, ExportAction)?> pickExport(BuildContext context) async {
  final l10n = context.l10n;
  final format = await _pick<ExportFormat>(context, l10n.exportChooseFormat, [
    (ExportFormat.excel, Icons.table_chart_outlined, l10n.exportExcel),
    (ExportFormat.pdf, Icons.picture_as_pdf_outlined, l10n.exportPdf),
  ]);
  if (format == null || !context.mounted) return null;
  final action = await _pick<ExportAction>(context, l10n.exportChooseAction, [
    (ExportAction.download, Icons.download_outlined, l10n.exportDownload),
    (ExportAction.share, Icons.share_outlined, l10n.exportShare),
  ]);
  return action == null ? null : (format, action);
}

Future<T?> _pick<T>(BuildContext context, String title,
        List<(T, IconData, String)> options) =>
    showModalBottomSheet<T>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: AppSpacing.space12),
          Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.space8),
          for (final (value, icon, label) in options)
            ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, value),
            ),
          const SizedBox(height: AppSpacing.space8),
        ]),
      ),
    );

/// Download (save-as dialog, then a "Saved" note) or share [bytes] as [name].
Future<void> deliverExport(BuildContext context, ExportAction action,
    Uint8List bytes, String name, String mimeType) async {
  if (action == ExportAction.share) return shareFile(bytes, name, mimeType);
  final messenger = ScaffoldMessenger.of(context);
  final saved = context.l10n.exportSaved;
  if (await saveFile(bytes, name)) {
    messenger.showSnackBar(SnackBar(content: Text('$saved: $name')));
  }
}
