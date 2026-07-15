import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_state.dart';
import '../../l10n/l10n_ext.dart';

class VittamUpdateDialog extends StatelessWidget {
  static const _packageId = 'com.vengurlatech.vittam';
  static const _brandGreen = Color(0xFF1DB954);

  final UpdateState state;

  const VittamUpdateDialog({super.key, required this.state});

  static Future<bool?> showIfNeeded(
    BuildContext context,
    UpdateState state,
  ) {
    if (!state.updateAvailable) return Future.value(null);
    return showDialog<bool>(
      context: context,
      barrierDismissible: !state.forceUpdate,
      builder: (_) => VittamUpdateDialog(state: state),
    );
  }

  Future<void> _openPlayStore() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_packageId',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;

    // dialogTitle/dialogMessage are optional remote-config overrides; when the
    // server does not supply them fall back to the localized defaults.
    final title =
        state.dialogTitle.isEmpty ? l10n.updateTitle : state.dialogTitle;
    final message =
        state.dialogMessage.isEmpty ? l10n.updateBody : state.dialogMessage;

    return PopScope(
      canPop: !state.forceUpdate,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: _brandGreen,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _brandGreen.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _brandGreen.withValues(alpha:0.4)),
                ),
                child: Text(
                  '${state.currentVersion}  →  ${state.latestVersion}',
                  style: textTheme.labelMedium?.copyWith(
                    color: _brandGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (state.forceUpdate) ...[
              const SizedBox(height: 12),
              Text(
                l10n.updateForceNote,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!state.forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.updateLater),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brandGreen),
            onPressed: () async {
              await _openPlayStore();
              if (context.mounted && !state.forceUpdate) {
                Navigator.pop(context, true);
              }
            },
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }
}
