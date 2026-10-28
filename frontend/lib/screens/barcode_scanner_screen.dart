import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Settings → Barcode Scanner. Bluetooth scanners are used in HID (keyboard)
/// mode: paired in the system Bluetooth settings, they type the code plus
/// Enter, which the billing screen's key handler already picks up. So the only
/// "connection" here is a shortcut to those settings and a box to test a scan.
class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  static const _channel = MethodChannel('vittam/system_settings');
  final _testCtrl = TextEditingController();
  final _testFocus = FocusNode();
  String? _result;
  bool _matched = false;

  // iOS has no public link to its Bluetooth page; pairing there is by hand.
  bool get _canOpenBluetooth =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void dispose() {
    _testCtrl.dispose();
    _testFocus.dispose();
    super.dispose();
  }

  Future<void> _openBluetooth() async {
    var ok = false;
    try {
      ok = defaultTargetPlatform == TargetPlatform.android
          ? await _channel.invokeMethod<bool>('openBluetooth') ?? false
          : await launchUrl(Uri.parse('ms-settings:bluetooth'));
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.scannerOpenFailed),
          backgroundColor: AppColors.error));
    }
  }

  void _onScanned(String code) {
    final l10n = context.l10n;
    code = code.trim();
    if (code.isEmpty) return;
    final hit = matchBarcode(ref.read(itemsProvider).valueOrNull ?? const [], code);
    setState(() {
      _matched = hit != null;
      _result = hit == null
          ? l10n.scannerTestUnknown(code)
          : l10n.scannerTestMatched(hit.variant == null
              ? hit.item.name
              : '${hit.item.name} – ${hit.variant!.label}');
    });
    // Ready for the next scan without another tap.
    _testCtrl.clear();
    _testFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsBarcodeScanner)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space16),
        children: [
          AppCard(child: Text(l10n.scannerSteps)),
          if (_canOpenBluetooth) ...[
            const SizedBox(height: AppSpacing.space12),
            FilledButton.icon(
              onPressed: _openBluetooth,
              icon: const Icon(Icons.bluetooth),
              label: Text(l10n.scannerOpenBluetooth),
            ),
          ],
          const SizedBox(height: AppSpacing.space24),
          Text(l10n.scannerTestTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.space8),
          TextField(
            controller: _testCtrl,
            focusNode: _testFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.scannerTestHint,
              prefixIcon: const Icon(Icons.qr_code_scanner),
            ),
            onSubmitted: _onScanned,
          ),
          if (_result != null) ...[
            const SizedBox(height: AppSpacing.space12),
            Row(
              children: [
                Icon(_matched ? Icons.check_circle : Icons.info_outline,
                    color: _matched ? AppColors.accent : AppColors.warning),
                const SizedBox(width: AppSpacing.space8),
                Expanded(child: Text(_result!)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
