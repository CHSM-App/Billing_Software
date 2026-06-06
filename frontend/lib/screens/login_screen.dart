import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../storage.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'register_screen.dart';
import 'otp_screen.dart';
import 'main_shell.dart';
import 'license_screen.dart';
import '../services/license_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _forgotPin() async {
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool sending = false;
    // Capture messenger before dialog opens so snackbars appear above the dialog
    final messenger = ScaffoldMessenger.of(context);

    // Step 1 — ask for phone number
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Forgot PIN'),
          content: Form(
            key: formKey,
            child: AppTextField(
              label: 'Registered phone number',
              controller: phoneCtrl,
              hint: '10-digit number',
              keyboardType: TextInputType.phone,
              maxLength: 10,
              prefixIcon: const Icon(Icons.phone_outlined,
                  size: 18, color: AppColors.textSecondary),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (!RegExp(r'^\d{10}$').hasMatch(v)) return 'Enter 10-digit number';
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              text: 'Send OTP',
              isLoading: sending,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setS(() => sending = true);
                try {
                  await sendOtp(phoneCtrl.text.trim(), 'forgot_pin');
                  if (ctx.mounted) Navigator.pop(ctx, phoneCtrl.text.trim());
                } on ApiException catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(e.message)));
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Failed to send OTP. Try again.')),
                  );
                } finally {
                  setS(() => sending = false);
                }
              },
            ),
          ],
        ),
      ),
    );

    if (!mounted || phone == null) return;

    // Step 2 — verify OTP; returns verified_token on success
    final verifiedToken = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(phone: phone, purpose: 'forgot_pin'),
      ),
    );

    if (!mounted || verifiedToken == null) return;

    // Step 3 — ask for new PIN
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    final pinFormKey = GlobalKey<FormState>();
    bool resetting = false;
    // Re-capture messenger (previous one may be stale after navigation)
    final pinMessenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Set New PIN'),
          content: Form(
            key: pinFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'New PIN',
                  controller: newPinCtrl,
                  hint: '4-digit PIN',
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  prefixIcon: const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.textSecondary),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'PIN must be 4 digits';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: 'Confirm PIN',
                  controller: confirmPinCtrl,
                  hint: 'Re-enter PIN',
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  prefixIcon: const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.textSecondary),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != newPinCtrl.text) return 'PINs do not match';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            PrimaryButton(
              text: 'Reset PIN',
              isLoading: resetting,
              onPressed: () async {
                if (!pinFormKey.currentState!.validate()) return;
                setS(() => resetting = true);
                try {
                  await resetPin(verifiedToken, newPinCtrl.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                  pinMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('PIN reset successfully. Please log in.'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } on ApiException catch (e) {
                  pinMessenger.showSnackBar(SnackBar(content: Text(e.message)));
                } catch (_) {
                  pinMessenger.showSnackBar(
                    const SnackBar(content: Text('Reset failed. Try again.')),
                  );
                } finally {
                  setS(() => resetting = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await login(
          _phoneController.text.trim(), _pinController.text.trim());
      final business = result['business'] as Map<String, dynamic>;
      await saveSession(
        accessToken: result['access_token'],
        refreshToken: result['refresh_token'],
        userId: result['user']['id'],
        userName: result['user']['name'],
        userRole: result['user']['role'],
        businessId: business['id'],
        businessName: business['name'],
        businessType: business['business_type'],
        inventoryEnabled: business['inventory_enabled'] == true,
        hasBarcodeScanner: business['has_barcode_scanner'] == true,
      );
      await ref.read(sessionProvider.notifier).refresh();
      ref.invalidate(itemsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(tablesProvider);
      ref.invalidate(billsProvider);
      ref.invalidate(billFilterProvider);
      ref.invalidate(reportProvider);
      ref.invalidate(cartProvider);
      if (!mounted) return;

      // License check after login — clear stale cache first so server is always authoritative
      await LicenseService.instance.clear();
      final licenseStatus = await LicenseService.instance.check(isOnline: true);
      if (!mounted) return;

      if (licenseStatus.state == LicenseState.blockedOffline ||
          licenseStatus.state == LicenseState.blockedSubscription ||
          licenseStatus.state == LicenseState.blockedPending) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LicenseBlockedScreen(
              reason: licenseStatus.state,
              onUnblocked: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MainShell(licenseStatus: licenseStatus),
                ),
              ),
            ),
          ),
        );
        return;
      }

      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => MainShell(licenseStatus: licenseStatus)));
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage =
          'Could not connect to server. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 720;

    return Scaffold(
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  Widget _buildNarrowLayout() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Center(child: _buildLogo()),
            ),
            Expanded(
              flex: 5,
              child: _buildFormCard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left panel — branding
        Expanded(
          child: Container(
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            child: Center(child: _buildLogo(large: true)),
          ),
        ),
        // Right panel — form
        Expanded(
          child: Container(
            color: AppColors.background,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildFormContent(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo({bool large = false}) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: large ? 80 : 64,
            height: large ? 80 : 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Icon(Icons.receipt_long_rounded,
                size: large ? 42 : 32, color: Colors.white),
          ),
          SizedBox(height: large ? AppSpacing.space16 : AppSpacing.space12),
          Text(
            'VBill',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: large ? 28 : 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Smart Billing Solution',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: large ? 15 : 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space24, AppSpacing.space32,
                AppSpacing.space24, AppSpacing.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _buildFormContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: AppSpacing.space8),
          Text(
            'Sign in to your billing account',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.space32),
          AppTextField(
            label: 'Phone number',
            controller: _phoneController,
            hint: '10-digit mobile number',
            keyboardType: TextInputType.phone,
            maxLength: 10,
            prefixIcon: const Icon(Icons.phone_outlined,
                size: 18, color: AppColors.textSecondary),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Phone is required';
              if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                return 'Enter a valid 10-digit number';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space16),
          AppTextField(
            label: 'PIN',
            controller: _pinController,
            hint: '4-digit PIN',
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            prefixIcon: const Icon(Icons.lock_outline,
                size: 18, color: AppColors.textSecondary),
            validator: (v) {
              if (v == null || v.isEmpty) return 'PIN is required';
              if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'PIN must be 4 digits';
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.space16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(AppSpacing.space12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: AppSpacing.space8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space24),
          PrimaryButton(
            text: 'Sign In',
            onPressed: _login,
            isLoading: _isLoading,
            icon: Icons.login_rounded,
          ),
          const SizedBox(height: AppSpacing.space12),
          Center(
            child: TextButton(
              onPressed: _forgotPin,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot PIN?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have an account? ",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Register'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
