import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../l10n/l10n_ext.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// What the owner chose on [LogoAdjustScreen]: the cropped logo (PNG) and
/// whether it should print on bills.
typedef LogoAdjustResult = ({Uint8List png, bool printLogo});

/// Lets the owner pinch-zoom and drag a freshly picked logo inside a frame
/// (square or wide) before it is uploaded, and decide right there whether it
/// prints on bills. The frame is captured as-is on a white background, so what
/// they see is exactly what gets uploaded.
class LogoAdjustScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final bool printLogo;

  const LogoAdjustScreen(
      {super.key, required this.imageBytes, required this.printLogo});

  @override
  State<LogoAdjustScreen> createState() => _LogoAdjustScreenState();
}

class _LogoAdjustScreenState extends State<LogoAdjustScreen> {
  final _frameKey = GlobalKey();
  final _transform = TransformationController();
  late bool _printLogo = widget.printLogo;
  bool _wide = false;
  bool _saving = false;

  /// Width in pixels of the uploaded logo. Plenty for a 576-dot receipt and
  /// the A4 invoice; compressToJpeg caps the size anyway.
  static const _outputWidth = 800.0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    final boundary =
        _frameKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image image =
        await boundary.toImage(pixelRatio: _outputWidth / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted) return;
    Navigator.pop<LogoAdjustResult>(
        context, (png: data!.buffer.asUint8List(), printLogo: _printLogo));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.logoAdjustTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            // Not scrollable on purpose: a scroll view would steal the vertical
            // drags meant for moving the logo inside the frame.
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.logoAdjustHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.space16),
                  // Square suits round/badge logos; wide suits text logos, which
                  // would otherwise print tiny inside a square.
                  Center(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.crop_square),
                            label: Text(l10n.logoShapeSquare)),
                        ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.crop_landscape),
                            label: Text(l10n.logoShapeWide)),
                      ],
                      selected: {_wide},
                      onSelectionChanged: (s) => setState(() {
                        _wide = s.first;
                        _transform.value = Matrix4.identity();
                      }),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _wide ? 2 : 1,
                        child: Container(
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: AppColors.primary, width: 2),
                          ),
                          child: RepaintBoundary(
                            key: _frameKey,
                            child: ClipRect(
                              child: ColoredBox(
                                color: Colors.white,
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  minScale: 0.3,
                                  maxScale: 6,
                                  boundaryMargin:
                                      const EdgeInsets.all(double.infinity),
                                  child: Center(
                                    child: Image.memory(widget.imageBytes,
                                        fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _transform.value = Matrix4.identity(),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: Text(l10n.logoReset),
                    ),
                  ),
                  CheckboxListTile(
                    value: _printLogo,
                    onChanged: (v) => setState(() => _printLogo = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.logoPrintOnBills,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  PrimaryButton(
                    text: l10n.logoSave,
                    isLoading: _saving,
                    onPressed: _saving ? null : _done,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
