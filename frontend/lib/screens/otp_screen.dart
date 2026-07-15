import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Shared OTP verification screen used for both registration and forgot-PIN.
///
/// [phone]   — the number the OTP was sent to (display only)
/// [purpose] — 'register' or 'forgot_pin'
///
/// On success:
/// - purpose='register'   → pops with `null` (caller proceeds to submit registration)
/// - purpose='forgot_pin' → pops with the `verified_token` String (caller opens reset-PIN dialog)
class OtpScreen extends StatefulWidget {
  final String phone;
  final String purpose;

  const OtpScreen({super.key, required this.phone, required this.purpose});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // 6 individual digit controllers + focus nodes
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;

  // Resend cooldown — 60 seconds
  int _resendCooldown = 60;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  String get _otp => _otpCtrls.map((c) => c.text).join();

  Future<void> _verify() async {
    final l10n = context.l10n;
    final otp = _otp;
    if (otp.length < 6) {
      setState(() => _error = l10n.otpEnterAllDigits);
      return;
    }
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      final result = await verifyOtp(widget.phone, otp, widget.purpose);
      if (!mounted) return;
      if (widget.purpose == 'forgot_pin') {
        Navigator.pop(context, result['verified_token'] as String);
      } else {
        Navigator.pop(context, true); // register flow — confirmed
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _clearOtp();
    } catch (_) {
      setState(() => _error = l10n.otpVerifyFailed);
      _clearOtp();
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    setState(() {
      _isResending = true;
      _error = null;
    });
    try {
      await sendOtp(widget.phone, widget.purpose);
      if (!mounted) return;
      _startCooldown();
      _clearOtp();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.otpResendSuccess)),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = l10n.otpResendFailed);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _clearOtp() {
    for (final c in _otpCtrls) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    // Auto-verify when last digit filled
    if (index == 5 && value.length == 1) {
      _verify();
    }
    setState(() => _error = null);
  }

  void _onKeyDown(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpCtrls[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maskedPhone =
        '${widget.phone.substring(0, 2)}XXXXXX${widget.phone.substring(8)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.purpose == 'forgot_pin'
            ? l10n.otpAppBarVerifyIdentity
            : l10n.otpAppBarVerifyPhone),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                    ),
                    child: const Icon(Icons.message_outlined,
                        size: 36, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.space24),

                // Title
                Text(
                  l10n.otpEnterCode,
                  style: Theme.of(context).textTheme.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space8),
                Text(
                  l10n.otpSentTo(maskedPhone),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space32),

                // OTP boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) => _buildOtpBox(i)),
                ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.space12),
                  Container(
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
                            _error!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
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
                  text: l10n.otpVerifyButton,
                  onPressed: _verify,
                  isLoading: _isVerifying,
                  icon: Icons.verified_outlined,
                ),

                const SizedBox(height: AppSpacing.space16),

                // Resend
                Center(
                  child: _resendCooldown > 0
                      ? Text(
                          l10n.otpResendCooldown(_resendCooldown),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        )
                      : TextButton(
                          onPressed: _isResending ? null : _resend,
                          child: _isResending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(l10n.otpResend),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 46,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) => _onKeyDown(index, event),
        child: TextFormField(
          controller: _otpCtrls[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.small),
              borderSide: BorderSide(
                color: _error != null ? AppColors.error : AppColors.border,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.small),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: AppColors.surface,
          ),
          onChanged: (v) => _onDigitChanged(index, v),
        ),
      ),
    );
  }
}
