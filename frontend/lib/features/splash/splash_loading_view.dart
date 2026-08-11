import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/app_theme.dart';

/// A static, non-animated twin of [VittamSplashScreen]'s visual.
///
/// Shown during the post-splash bootstrap (`_AppEntry`) and as MainShell's
/// loading state, so the user sees ONE continuous branded loading screen from
/// launch until the first page is ready — no bare spinner flashes between the
/// splash and the app. It intentionally has no entry animation: it holds the
/// exact frame the splash settled on, so the hand-off is seamless.
class SplashLoadingView extends StatelessWidget {
  const SplashLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Decorative glow — top-right (matches the splash)
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
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
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
                // Progress bar — same as the splash's
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.space48),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: LinearProgressIndicator(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                      minHeight: 3,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space48),
              ],
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
