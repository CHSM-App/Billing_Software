import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_state.dart';

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
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !state.forceUpdate,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          state.dialogTitle,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: _brandGreen,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.dialogMessage, style: textTheme.bodyMedium),
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
                'यह अपडेट जरूरी है। कृपया अपडेट करके जारी रखें।',
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
              child: const Text('बाद में'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brandGreen),
            onPressed: () async {
              await _openPlayStore();
              if (context.mounted && !state.forceUpdate) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('अभी अपडेट करें'),
          ),
        ],
      ),
    );
  }
}
