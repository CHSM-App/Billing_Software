import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_provider.dart';
import '../update/vittam_update_dialog.dart';
import '../../l10n/l10n_ext.dart';
import '../../theme/app_theme.dart';

class VittamSplashScreen extends ConsumerStatefulWidget {
  const VittamSplashScreen({super.key});

  @override
  ConsumerState<VittamSplashScreen> createState() => _VittamSplashScreenState();
}

class _VittamSplashScreenState extends ConsumerState<VittamSplashScreen>
    with SingleTickerProviderStateMixin {
  static const _minSplashDuration = Duration(milliseconds: 2000);

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slideUp = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    _animController.forward();
    _run();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    // Wait minimum 2 seconds then run the update gate.
    await Future.delayed(_minSplashDuration);
    if (!mounted) return;

    // Firebase Remote Config decides WHETHER an update is needed and whether
    // it's forced (with a custom message). If it forces, the gate blocks and we
    // do NOT enter the app; the dialog's "Update now" opens the Play Store.
    final proceed = await _remoteConfigGate();
    if (!proceed) return; // forced update — stay on the gate

    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  /// Reads the RC-driven update decision and shows [VittamUpdateDialog].
  /// Returns true if the app may proceed, false if a FORCED update blocks it.
  Future<bool> _remoteConfigGate() async {
    // The update dialog's "Update now" opens the Play Store, so this gate only
    // makes sense on Android. On iOS/web/desktop, skip it and open the app.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final state = await ref.read(updateCheckProvider.future);
      if (!state.updateAvailable) return true;

      if (!mounted) return true;
      // Non-dismissible when forced (barrierDismissible + PopScope handle it).
      await VittamUpdateDialog.showIfNeeded(context, state);

      // If forced, the only way past the dialog is to update — so block here.
      return !state.forceUpdate;
    } catch (e) {
      debugPrint('remote-config update gate error: $e');
      return true; // never let an RC failure lock the user out
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final versionAsync = ref.watch(appVersionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Decorative glow — top-right
          Positioned(
            top: -size.width * 0.25,
            right: -size.width * 0.25,
            child: _GlowCircle(
              size: size.width * 0.75,
              color: AppColors.primary.withValues(alpha: 0.07),
            ),
          ),
          // Decorative glow — bottom-left
          Positioned(
            bottom: -size.width * 0.3,
            left: -size.width * 0.3,
            child: _GlowCircle(
              size: size.width * 0.85,
              color: AppColors.accent.withValues(alpha: 0.06),
            ),
          ),

          SafeArea(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                return Opacity(
                  opacity: _fadeIn.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideUp.value),
                    child: Column(
                      children: [
                        const Spacer(flex: 3),

                        // Logo card
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            boxShadow: AppShadow.medium,
                            border: Border.all(color: AppColors.border),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.space24),

                        // App name
                        Text(
                          l10n.appName,
                          style: AppFont.style(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.8,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.space8),

                        // Tagline
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space24,
                          ),
                          child: Text(
                            l10n.splashTagline,
                            textAlign: TextAlign.center,
                            style: AppFont.style(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),

                        const Spacer(flex: 3),

                        // Progress bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space48,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.small),
                            child: LinearProgressIndicator(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                              minHeight: 3,
                            ),
                          ),
                        ),

                        const SizedBox(height: AppSpacing.space16),

                        // Version
                        versionAsync.when(
                          data: (v) => Text(
                            'v$v',
                            style: AppFont.style(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textDisabled,
                            ),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),

                        const SizedBox(height: AppSpacing.space32),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
