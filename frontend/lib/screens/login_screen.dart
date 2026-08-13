import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../storage.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/language_selector.dart';
import 'register_screen.dart';
import 'otp_screen.dart';
import 'main_shell.dart';
import 'license_screen.dart';
import '../services/license_service.dart';
import '../services/notification_service.dart';

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
  bool _isPendingActivation = false;

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
    final l10n = context.l10n;

    // Step 1 — ask for phone number
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l10n.forgotPinTitle),
          content: Form(
            key: formKey,
            child: AppTextField(
              label: l10n.forgotPinPhoneLabel,
              controller: phoneCtrl,
              hint: l10n.forgotPinPhoneHint,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              prefixIcon: const Icon(Icons.phone_outlined,
                  size: 18, color: AppColors.textSecondary),
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.commonRequired;
                if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                  return l10n.forgotPinPhoneInvalid;
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
            PrimaryButton(
              text: l10n.forgotPinSendOtp,
              isLoading: sending,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setS(() => sending = true);
                try {
                  await sendOtp(phoneCtrl.text.trim(), 'forgot_pin');
                  if (ctx.mounted) Navigator.pop(ctx, phoneCtrl.text.trim());
                } on ApiException catch (e) {
                  messenger.showSnackBar(SnackBar(
                      content: Text(sanitizeUiErrorMessage(e,
                          fallback: l10n.forgotPinSendFailed))));
                } catch (_) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.forgotPinSendFailed)),
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
          title: Text(l10n.forgotPinSetNewTitle),
          content: Form(
            key: pinFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: l10n.forgotPinNewLabel,
                  controller: newPinCtrl,
                  hint: l10n.loginPinHint,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  prefixIcon: const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.textSecondary),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.commonRequired;
                    if (!RegExp(r'^\d{4}$').hasMatch(v)) {
                      return l10n.loginPinInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: l10n.forgotPinConfirmLabel,
                  controller: confirmPinCtrl,
                  hint: l10n.forgotPinConfirmHint,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  prefixIcon: const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.textSecondary),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.commonRequired;
                    if (v != newPinCtrl.text) return l10n.forgotPinMismatch;
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            PrimaryButton(
              text: l10n.forgotPinReset,
              isLoading: resetting,
              onPressed: () async {
                if (!pinFormKey.currentState!.validate()) return;
                setS(() => resetting = true);
                try {
                  await resetPin(verifiedToken, newPinCtrl.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                  pinMessenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.forgotPinResetSuccess),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } on ApiException catch (e) {
                  pinMessenger.showSnackBar(SnackBar(
                      content: Text(sanitizeUiErrorMessage(e,
                          fallback: l10n.forgotPinResetFailed))));
                } catch (_) {
                  pinMessenger.showSnackBar(
                    SnackBar(content: Text(l10n.forgotPinResetFailed)),
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
      _isPendingActivation = false;
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
        gstEnabled: business['gst_enabled'] == true,
        roundOffEnabled: business['round_off_enabled'] == true,
      );
      // Cache GST invoice details so the thermal receipt can print GSTIN offline.
      await saveGstProfile(
        gstNumber: business['gst_number'] as String?,
        businessAddress: business['address'] as String?,
        defaultSacCode: business['default_sac_code'] as String?,
        fssaiNumber: business['fssai_number'] as String?,
      );
      NotificationService.instance.init();
      await ref.read(sessionProvider.notifier).refresh();
      ref.invalidate(itemsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(tablesProvider);
      ref.invalidate(billsProvider);
      ref.invalidate(billFilterProvider);
      ref.invalidate(reportProvider);
      ref.invalidate(cartProvider);
      if (!mounted) return;

      // Device-access gate FIRST, using the policy in the login response itself.
      // This is authoritative and network-free, so it works even if the later
      // /health or /license calls can't reach the server (flaky mobile network).
      final deviceState = await LicenseService.instance.checkDevicePolicy(
        allowMobile: business['allow_mobile'] as bool?,
        allowDesktop: business['allow_desktop'] as bool?,
      );
      if (!mounted) return;
      if (deviceState == LicenseState.blockedDevice) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LicenseBlockedScreen(
              reason: LicenseState.blockedDevice,
              onUnblocked: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
              ),
            ),
          ),
        );
        return;
      }

      // License check after login — clear stale cache first so server is always
      // authoritative. clear() wipes the device-policy cache too, so re-cache it
      // from the login response right after (the /license fetch will refresh it).
      await LicenseService.instance.clear();
      await LicenseService.instance.cacheDevicePolicy(
        allowMobile: business['allow_mobile'] as bool?,
        allowDesktop: business['allow_desktop'] as bool?,
      );
      final licenseStatus = await LicenseService.instance.check(isOnline: true);
      if (!mounted) return;

      if (licenseStatus.sessionInvalid) {
        // Freshly-written session couldn't be read back / was rejected —
        // don't show a misleading offline screen, let the user retry login.
        await ref.read(sessionProvider.notifier).clear();
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Could not verify your session. Please try logging in again.';
        });
        return;
      }

      if (licenseStatus.state == LicenseState.blockedOffline ||
          licenseStatus.state == LicenseState.blockedSubscription ||
          licenseStatus.state == LicenseState.blockedPending ||
          licenseStatus.state == LicenseState.blockedDevice) {
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
      final l10n = context.l10n;
      if (e.statusCode == 403) {
        setState(() => _isPendingActivation = true);
      } else if (e.statusCode == 404) {
        setState(() => _errorMessage = l10n.loginNoAccountFound);
      } else if (e.statusCode == 401) {
        setState(() => _errorMessage = l10n.loginIncorrectPin);
      } else if (e.statusCode == 423) {
        setState(() =>
            _errorMessage = e.serverMessage ?? l10n.loginAccountLocked);
      } else {
        setState(() =>
            _errorMessage = e.serverMessage ?? l10n.loginGenericError);
      }
    } catch (e) {
      setState(() => _errorMessage = context.l10n.loginConnectionError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 720;

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              boxShadow: AppShadow.medium,
            ),
            padding: const EdgeInsets.all(10),
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
          SizedBox(height: large ? AppSpacing.space16 : AppSpacing.space12),
          Text(
            context.l10n.appName,
            style: AppFont.style(
              fontSize: large ? 28 : 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.appTagline,
            textAlign: TextAlign.center,
            style: AppFont.style(
              fontSize: large ? 15 : 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          SizedBox(height: large ? AppSpacing.space24 : AppSpacing.space16),
          const LanguageToggle(),
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
    final l10n = context.l10n;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.loginTitle,
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: AppSpacing.space8),
          Text(
            l10n.loginSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.space32),
          AppTextField(
            label: l10n.loginPhone,
            controller: _phoneController,
            hint: l10n.loginPhoneHint,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            prefixIcon: const Icon(Icons.phone_outlined,
                size: 18, color: AppColors.textSecondary),
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.loginPhoneRequired;
              if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                return l10n.loginPhoneInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space16),
          AppTextField(
            label: l10n.loginPin,
            controller: _pinController,
            hint: l10n.loginPinHint,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            prefixIcon: const Icon(Icons.lock_outline,
                size: 18, color: AppColors.textSecondary),
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.loginPinRequired;
              if (!RegExp(r'^\d{4}$').hasMatch(v)) return l10n.loginPinInvalid;
              return null;
            },
          ),
          if (_isPendingActivation) ...[
            const SizedBox(height: AppSpacing.space16),
            Container(
              padding: const EdgeInsets.all(AppSpacing.space12),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: AppSpacing.space8),
                      Text(
                        l10n.loginPendingTitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.loginPendingBody,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const SupportContactRow(color: AppColors.warning),
                ],
              ),
            ),
          ] else if (_errorMessage != null) ...[
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
            text: l10n.loginSignIn,
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
                l10n.loginForgotPin,
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
              Flexible(
                child: Text(
                  l10n.loginNoAccount,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
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
                child: Text(l10n.loginRegister),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
