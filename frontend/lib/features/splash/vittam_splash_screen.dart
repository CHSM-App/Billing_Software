import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/update/update_provider.dart';
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
    // Wait minimum 2 seconds then check for update
    await Future.delayed(_minSplashDuration);
    if (!mounted) return;

    await _checkUpdate();

    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  /// Checks Play Store for updates directly — no Firebase RC needed.
  ///
  /// Priority is set via deploy.js at publish time:
  ///   0–3 → bottom sheet popup  (optional, user can dismiss)
  ///   4–5 → full screen forced  (user cannot dismiss)
  ///
  /// Silently ignored in debug builds or sideloaded APKs.
  Future<void> _checkUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      debugPrint('in_app_update: availability=${info.updateAvailability}, priority=${info.updatePriority}');

      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      if (info.updatePriority >= 4) {
        // Full-screen forced update — user cannot dismiss
        await InAppUpdate.performImmediateUpdate();
      } else {
        // Bottom sheet — user can dismiss; download happens in background
        final result = await InAppUpdate.startFlexibleUpdate();
        debugPrint('in_app_update: flexible result=$result');
        // Note: completeFlexibleUpdate() must be called only after
        // InstallStatus.downloaded — Play Store notifies user when ready
      }
    } catch (e, st) {
      debugPrint('in_app_update ERROR: $e\n$st');
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
