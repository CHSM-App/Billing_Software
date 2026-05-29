import 'package:flutter/material.dart';
import '../api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

// ---------------------------------------------------------------------------
// BusinessProfileScreen
//
// Lets the owner view and update:
//   • Basic info   — name, phone, email, website, business type (read-only)
//   • Address      — address, city, state, pincode
//   • Tax info     — GSTIN, PAN
//   • Billing      — bill prefix, footer note
//
// Navigation:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => const BusinessProfileScreen(),
//   ));
// ---------------------------------------------------------------------------

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;

  // ── Controllers ──────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl         = TextEditingController();
  final _phoneCtrl        = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _websiteCtrl      = TextEditingController();
  final _addressCtrl      = TextEditingController();
  final _cityCtrl         = TextEditingController();
  final _stateCtrl        = TextEditingController();
  final _pincodeCtrl      = TextEditingController();
  final _gstCtrl          = TextEditingController();
  final _panCtrl          = TextEditingController();
  final _billPrefixCtrl   = TextEditingController();
  final _footerNoteCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _websiteCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _gstCtrl.dispose();
    _panCtrl.dispose();
    _billPrefixCtrl.dispose();
    _footerNoteCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await getBusinessProfile();
      _populateControllers(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.toString());
    }
  }

  void _populateControllers(Map<String, dynamic> p) {
    _nameCtrl.text        = p['name']             ?? '';
    _phoneCtrl.text       = p['phone']            ?? '';
    _emailCtrl.text       = p['email']            ?? '';
    _websiteCtrl.text     = p['website']          ?? '';
    _addressCtrl.text     = p['address']          ?? '';
    _cityCtrl.text        = p['city']             ?? '';
    _stateCtrl.text       = p['state']            ?? '';
    _pincodeCtrl.text     = p['pincode']          ?? '';
    _gstCtrl.text         = p['gst_number']       ?? '';
    _panCtrl.text         = p['pan_number']       ?? '';
    _billPrefixCtrl.text  = p['bill_prefix']      ?? 'INV';
    _footerNoteCtrl.text  = p['bill_footer_note'] ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{};

      void addIfChanged(String key, TextEditingController ctrl, String? original) {
        final v = ctrl.text.trim();
        final orig = (original ?? '').trim();
        if (v != orig) payload[key] = v.isEmpty ? null : v;
      }

      addIfChanged('name',             _nameCtrl,        _profile?['name']);
      addIfChanged('phone',            _phoneCtrl,       _profile?['phone']);
      addIfChanged('email',            _emailCtrl,       _profile?['email']);
      addIfChanged('website',          _websiteCtrl,     _profile?['website']);
      addIfChanged('address',          _addressCtrl,     _profile?['address']);
      addIfChanged('city',             _cityCtrl,        _profile?['city']);
      addIfChanged('state',            _stateCtrl,       _profile?['state']);
      addIfChanged('pincode',          _pincodeCtrl,     _profile?['pincode']);
      addIfChanged('gst_number',       _gstCtrl,         _profile?['gst_number']);
      addIfChanged('pan_number',       _panCtrl,         _profile?['pan_number']);
      addIfChanged('bill_prefix',      _billPrefixCtrl,  _profile?['bill_prefix']);
      addIfChanged('bill_footer_note', _footerNoteCtrl,  _profile?['bill_footer_note']);

      if (payload.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No changes to save')),
          );
        }
        return;
      }

      final updated = await updateBusinessProfile(payload);
      _populateControllers(updated);
      setState(() => _profile = updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Business Profile'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (!_loading)
            _saving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _save,
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.space16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSection(
                            context,
                            label: 'BASIC INFO',
                            icon: Icons.storefront_outlined,
                            iconColor: AppColors.primary,
                            children: [
                              _buildField(
                                controller: _nameCtrl,
                                label: 'Business Name',
                                hint: 'e.g. Kamble Provisions',
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildField(
                                controller: _phoneCtrl,
                                label: 'Phone',
                                hint: '10-digit mobile number',
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  if (!RegExp(r'^\d{10}$').hasMatch(v.trim())) {
                                    return 'Must be 10 digits';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildField(
                                controller: _emailCtrl,
                                label: 'Email (optional)',
                                hint: 'owner@example.com',
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(v.trim())) {
                                    return 'Invalid email address';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildField(
                                controller: _websiteCtrl,
                                label: 'Website (optional)',
                                hint: 'https://example.com',
                                keyboardType: TextInputType.url,
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildReadOnly(
                                context,
                                label: 'Business Type',
                                value: _formatType(_profile?['business_type'] ?? ''),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space24),

                          _buildSection(
                            context,
                            label: 'ADDRESS',
                            icon: Icons.location_on_outlined,
                            iconColor: const Color(0xFF0EA5E9),
                            children: [
                              _buildField(
                                controller: _addressCtrl,
                                label: 'Street Address',
                                hint: 'Shop No. 5, Market Road',
                                maxLines: 2,
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildField(
                                      controller: _cityCtrl,
                                      label: 'City',
                                      hint: 'Vengurla',
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.space12),
                                  Expanded(
                                    child: _buildField(
                                      controller: _stateCtrl,
                                      label: 'State',
                                      hint: 'Maharashtra',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildField(
                                controller: _pincodeCtrl,
                                label: 'Pincode',
                                hint: '416523',
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) {
                                    return '6-digit pincode';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space24),

                          _buildSection(
                            context,
                            label: 'TAX INFO',
                            icon: Icons.receipt_outlined,
                            iconColor: const Color(0xFF7C3AED),
                            children: [
                              _buildField(
                                controller: _gstCtrl,
                                label: 'GSTIN (optional)',
                                hint: '27ABCDE1234F1Z5',
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 15,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$')
                                      .hasMatch(v.trim())) {
                                    return 'Invalid GSTIN format';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildField(
                                controller: _panCtrl,
                                label: 'PAN (optional)',
                                hint: 'ABCDE1234F',
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 10,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$')
                                      .hasMatch(v.trim())) {
                                    return 'Invalid PAN format';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space24),

                          _buildSection(
                            context,
                            label: 'BILLING',
                            icon: Icons.print_outlined,
                            iconColor: AppColors.warning,
                            children: [
                              _buildField(
                                controller: _billPrefixCtrl,
                                label: 'Bill Number Prefix',
                                hint: 'INV',
                                maxLength: 10,
                                helperText: 'Bills will be numbered INV-0001, INV-0002, …',
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  if (!RegExp(r'^[A-Za-z0-9\-/]+$').hasMatch(v.trim())) {
                                    return 'Letters, numbers, hyphens, slashes only';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: AppSpacing.space12),
                              _buildField(
                                controller: _footerNoteCtrl,
                                label: 'Bill Footer Note (optional)',
                                hint: 'Thank you for shopping with us!',
                                maxLines: 3,
                                maxLength: 500,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space32),

                          PrimaryButton(
                            text: _saving ? 'Saving…' : 'Save Profile',
                            onPressed: _saving ? null : _save,
                          ),
                          const SizedBox(height: AppSpacing.space32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Section card ──────────────────────────────────────────────────────────

  Widget _buildSection(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.space8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadow.small,
          ),
          padding: const EdgeInsets.all(AppSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  // ── Form field ────────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: 2,
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space12, vertical: AppSpacing.space12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  // ── Read-only display (non-editable fields) ───────────────────────────────

  Widget _buildReadOnly(BuildContext context,
      {required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space12, vertical: AppSpacing.space12),
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(AppRadius.small),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatType(String type) {
    return switch (type) {
      'retail'                  => 'Retail Shop',
      'restaurant_with_tables'  => 'Restaurant (with tables)',
      'restaurant_no_tables'    => 'Restaurant (takeaway)',
      _                         => type,
    };
  }
}
