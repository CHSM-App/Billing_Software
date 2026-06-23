import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/update/update_provider.dart';
import '../../core/update/update_state.dart';
import '../../theme/app_theme.dart';
import '../update/vittam_update_dialog.dart';

class VittamSplashScreen extends ConsumerStatefulWidget {
  const VittamSplashScreen({super.key});

  @override
  ConsumerState<VittamSplashScreen> createState() => _VittamSplashScreenState();
}

class _VittamSplashScreenState extends ConsumerState<VittamSplashScreen>
    with SingleTickerProviderStateMixin {
  static const _minSplashDuration = Duration(milliseconds: 2000);

  bool _navigated = false;
  bool _timerDone = false;
  bool _updateCheckDone = false;
  UpdateState? _pendingState;
  Object? _pendingError;

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

    Future.delayed(_minSplashDuration, () {
      if (!mounted) return;
      _timerDone = true;
      _tryNavigate();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onUpdateData(UpdateState state) {
    _pendingState = state;
    _updateCheckDone = true;
    _tryNavigate();
  }

  void _onUpdateError(Object error) {
    _pendingError = error;
    _updateCheckDone = true;
    _tryNavigate();
  }

  Future<void> _tryNavigate() async {
    if (!mounted || _navigated) return;
    if (!_timerDone || !_updateCheckDone) return;

    _navigated = true;

    if (_pendingError != null) {
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    final state = _pendingState!;
    if (state.updateAvailable && mounted) {
      await VittamUpdateDialog.showIfNeeded(context, state);
    }

    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UpdateState>>(updateCheckProvider, (_, next) {
      next.when(
        data: _onUpdateData,
        error: (e, __) => _onUpdateError(e),
        loading: () {},
      );
    });

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
                          'Vittam',
                          style: GoogleFonts.inter(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.8,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.space8),

                        // Tagline
                        Text(
                          'Smart Billing for Indian Businesses',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.2,
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
                            style: GoogleFonts.inter(
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
