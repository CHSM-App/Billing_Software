import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import '../api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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
  bool _hasBarcodeScanner = false;
  bool _isLoading = false;
  String? _errorMessage;

  bool get _isRetail => _businessType == 'retail';
  bool get _isWindows {
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await register(
        businessName: _businessNameController.text.trim(),
        businessType: _businessType,
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        phone: _businessPhoneController.text.trim(),
        inventoryEnabled: _isRetail && _inventoryEnabled,
        hasBarcodeScanner: _isRetail && _isWindows && _hasBarcodeScanner,
        ownerName: _ownerNameController.text.trim(),
        ownerPhone: _ownerPhoneController.text.trim(),
        pin: _pinController.text.trim(),
      );

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Registration submitted'),
          content: const Text(
            'Registration successful. Account pending verification.\n\nPlease contact support to activate your account.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to login
              },
              child: const Text('Back to Login'),
            ),
          ],
        ),
      );
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
      appBar: AppBar(title: const Text('Register Business')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Business details', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.space24),

                  AppTextField(
                    label: 'Business name',
                    controller: _businessNameController,
                    hint: 'e.g. Sharma General Store',
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.space16),

                  // Business type
                  Text('Business type', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.space8),
                  RadioGroup<String>(
                    groupValue: _businessType,
                    onChanged: (v) => setState(() {
                      _businessType = v!;
                      if (!_isRetail) {
                        _inventoryEnabled = false;
                        _hasBarcodeScanner = false;
                      }
                    }),
                    child: Column(
                      children: [
                        ('retail', 'Retail Shop'),
                        ('restaurant_with_tables', 'Restaurant (with tables)'),
                        ('restaurant_no_tables', 'Restaurant (takeaway / counter)'),
                      ]
                          .map((entry) => RadioListTile<String>(
                                value: entry.$1,
                                title: Text(entry.$2,
                                    style: Theme.of(context).textTheme.bodyMedium),
                                contentPadding: EdgeInsets.zero,
                              ))
                          .toList(),
                    ),
                  ),

                  if (_isRetail) ...[
                    const SizedBox(height: AppSpacing.space8),
                    SwitchListTile(
                      value: _inventoryEnabled,
                      onChanged: (v) => setState(() => _inventoryEnabled = v),
                      title: Text('Enable inventory tracking',
                          style: Theme.of(context).textTheme.bodyMedium),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_isWindows)
                      SwitchListTile(
                        value: _hasBarcodeScanner,
                        onChanged: (v) => setState(() => _hasBarcodeScanner = v),
                        title: Text('Has USB barcode scanner',
                            style: Theme.of(context).textTheme.bodyMedium),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],

                  const SizedBox(height: AppSpacing.space16),
                  AppTextField(
                    label: 'Business phone',
                    controller: _businessPhoneController,
                    hint: '10-digit number',
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!RegExp(r'^\d{10}$').hasMatch(v)) return 'Enter a valid 10-digit number';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  AppTextField(
                    label: 'Address (optional)',
                    controller: _addressController,
                    hint: 'Shop address',
                  ),

                  const SizedBox(height: AppSpacing.space32),
                  Text('Owner details', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.space24),

                  AppTextField(
                    label: 'Your name',
                    controller: _ownerNameController,
                    hint: 'Full name',
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  AppTextField(
                    label: 'Your phone number',
                    controller: _ownerPhoneController,
                    hint: '10-digit number (used to log in)',
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
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
                      if (v == null || v.isEmpty) return 'Required';
                      if (!RegExp(r'^\d{4}$').hasMatch(v)) return 'PIN must be 4 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  AppTextField(
                    label: 'Confirm PIN',
                    controller: _confirmPinController,
                    hint: 'Re-enter PIN',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v != _pinController.text) return 'PINs do not match';
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
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.space32),
                  PrimaryButton(
                    text: 'Register',
                    onPressed: _register,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: AppSpacing.space48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
