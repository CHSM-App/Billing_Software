import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/language_selector.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  String _businessType = 'retail';
  bool _inventoryEnabled = false;
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;


  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
    _businessPhoneController.dispose();
    _ownerNameController.dispose();
    _ownerPhoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    final ownerPhone = _ownerPhoneController.text.trim();

    // Step 1 — send OTP to owner's phone
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await sendOtp(ownerPhone, 'register');
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.serverMessage ?? e.message);
      return;
    } catch (_) {
      setState(() => _errorMessage = l10n.registerOtpSendFailed);
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    // Step 2 — open OTP screen; returns true on success, null if user went back
    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(phone: ownerPhone, purpose: 'register'),
      ),
    );

    if (!mounted || verified != true) return;

    // Step 3 — OTP confirmed, submit registration
    await _submitRegistration();
  }

  Future<void> _submitRegistration() async {
    final l10n = context.l10n;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await register(
        businessName: _businessNameController.text.trim(),
        businessType: _businessType,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        phone: _businessPhoneController.text.trim(),
        inventoryEnabled: _inventoryEnabled,
        hasBarcodeScanner: true,
        ownerName: _ownerNameController.text.trim(),
        ownerPhone: _ownerPhoneController.text.trim(),
        pin: _pinController.text.trim(),
      );

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(Icons.check_rounded,
                    size: 20, color: AppColors.success),
              ),
              const SizedBox(width: AppSpacing.space12),
              Expanded(child: Text(l10n.registerSuccessTitle)),
            ],
          ),
          content: Text(l10n.registerSuccessBody),
          actions: [
            PrimaryButton(
              text: l10n.registerBackToLogin,
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      setState(() => _errorMessage =
          sanitizeUiErrorMessage(e, fallback: l10n.loginConnectionError));
    } catch (_) {
      setState(() => _errorMessage = l10n.loginConnectionError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.registerAppBarTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: LanguageToggle(),
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    _buildSectionCard(
                      icon: Icons.storefront_outlined,
                      title: l10n.registerSectionBusinessDetails,
                      color: AppColors.primary,
                      children: [
                        AppTextField(
                          label: l10n.registerBusinessName,
                          controller: _businessNameController,
                          hint: l10n.registerBusinessNameHint,
                          capitalizeWords: true,
                          prefixIcon: const Icon(Icons.store_outlined,
                              size: 18, color: AppColors.textSecondary),
                          validator: (v) => v == null || v.isEmpty
                              ? l10n.commonRequired
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.space16),
                        AppTextField(
                          label: l10n.registerBusinessPhone,
                          controller: _businessPhoneController,
                          hint: l10n.registerBusinessPhoneHint,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          prefixIcon: const Icon(Icons.phone_outlined,
                              size: 18, color: AppColors.textSecondary),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.commonRequired;
                            }
                            if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                              return l10n.loginPhoneInvalid;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.space16),
                        AppTextField(
                          label: l10n.registerAddress,
                          controller: _addressController,
                          hint: l10n.registerAddressHint,
                          capitalizeWords: true,
                          prefixIcon: const Icon(Icons.location_on_outlined,
                              size: 18, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    _buildSectionCard(
                      icon: Icons.category_outlined,
                      title: l10n.registerSectionBusinessType,
                      color: AppColors.accent,
                      children: [
                        ...([
                          ('retail', l10n.businessTypeRetail,
                              Icons.shopping_bag_outlined),
                          ('restaurant',
                              l10n.businessTypeRestaurant,
                              Icons.table_restaurant_outlined),
                        ].map((entry) => _buildTypeOption(
                              entry.$1,
                              entry.$2,
                              entry.$3,
                            ))),
                        // Inventory tracking is offered to every business type
                        // (retail stock, liquor bottles, restaurant raw materials).
                        const SizedBox(height: AppSpacing.space8),
                        const Divider(),
                        const SizedBox(height: AppSpacing.space8),
                        _buildToggleTile(
                          icon: Icons.inventory_2_outlined,
                          title: l10n.registerInventoryTitle,
                          subtitle: l10n.registerInventorySubtitle,
                          value: _inventoryEnabled,
                          onChanged: (v) =>
                              setState(() => _inventoryEnabled = v),
                        ),
                        // Barcode scanning is enabled by default for every
                        // business, so no toggle is shown here.
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    _buildSectionCard(
                      icon: Icons.person_outlined,
                      title: l10n.registerSectionOwnerDetails,
                      color: const Color(0xFF7C3AED),
                      children: [
                        AppTextField(
                          label: l10n.registerOwnerName,
                          controller: _ownerNameController,
                          hint: l10n.registerOwnerNameHint,
                          capitalizeWords: true,
                          prefixIcon: const Icon(Icons.person_outline,
                              size: 18, color: AppColors.textSecondary),
                          validator: (v) => v == null || v.isEmpty
                              ? l10n.commonRequired
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.space16),
                        AppTextField(
                          label: l10n.registerOwnerPhone,
                          controller: _ownerPhoneController,
                          hint: l10n.registerOwnerPhoneHint,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          prefixIcon: const Icon(Icons.phone_outlined,
                              size: 18, color: AppColors.textSecondary),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.commonRequired;
                            }
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
                            if (v == null || v.isEmpty) {
                              return l10n.commonRequired;
                            }
                            if (!RegExp(r'^\d{4}$').hasMatch(v)) {
                              return l10n.loginPinInvalid;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.space16),
                        AppTextField(
                          label: l10n.registerConfirmPin,
                          controller: _confirmPinController,
                          hint: l10n.forgotPinConfirmHint,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 4,
                          prefixIcon: const Icon(Icons.lock_outline,
                              size: 18, color: AppColors.textSecondary),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.commonRequired;
                            }
                            if (v != _pinController.text) {
                              return l10n.forgotPinMismatch;
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.space16),
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
                                _errorMessage!,
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
                      text: l10n.registerCreateAccount,
                      onPressed: _register,
                      isLoading: _isLoading,
                      icon: Icons.rocket_launch_outlined,
                    ),
                    const SizedBox(height: AppSpacing.space48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                AppSpacing.space16, AppSpacing.space16, AppSpacing.space12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: AppSpacing.space12),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOption(String value, String label, IconData icon) {
    final selected = _businessType == value;
    return GestureDetector(
      onTap: () => setState(() {
        _businessType = value;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: AppSpacing.space8),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space12, vertical: AppSpacing.space12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? AppColors.primaryDark
                          : AppColors.textPrimary,
                    ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color:
                      selected ? AppColors.primary : AppColors.textDisabled,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      )),
              Text(subtitle,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
