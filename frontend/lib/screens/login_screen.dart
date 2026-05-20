import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../storage.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'register_screen.dart';
import 'main_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await login(_phoneController.text.trim(), _pinController.text.trim());
      final business = result['business'] as Map<String, dynamic>;
      await saveSession(
        token: result['token'],
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
      // Invalidate all business-scoped providers so the new account's data loads fresh
      ref.invalidate(itemsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(tablesProvider);
      ref.invalidate(billsProvider);
      ref.invalidate(billFilterProvider);
      ref.invalidate(reportProvider);
      ref.invalidate(cartProvider);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell()));
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not connect to server. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.space48),
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
                    const SizedBox(height: AppSpacing.space48),
                    AppTextField(
                      label: 'Phone number',
                      controller: _phoneController,
                      hint: '10-digit mobile number',
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Phone is required';
                        if (!RegExp(r'^\d{10}$').hasMatch(v)) return 'Enter a valid 10-digit number';
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
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'PIN is required';
                        if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'PIN must be 4 digits';
                        return null;
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.space16),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.space12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.error,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.space24),
                    PrimaryButton(
                      text: 'Login',
                      onPressed: _login,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                      child: const Text('Register new business'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
