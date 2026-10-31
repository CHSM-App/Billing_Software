import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../services/bill_settings.dart';
import '../theme/app_theme.dart';
import '../utils/text_formatters.dart'
    show UpperCaseTextFormatter, isIndianMobile;
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

/// Owner's "Billing Setup": what prints on a bill. Ticked parts show on every
/// printed bill (thermal, A4/A5) and on the shared receipt link.
///
/// Saved as businesses.bill_settings (see services/bill_settings.dart), plus
/// the older print_logo flag and bill_footer_note (the terms text).
class BillingSetupScreen extends ConsumerStatefulWidget {
  const BillingSetupScreen({super.key});

  @override
  ConsumerState<BillingSetupScreen> createState() => _BillingSetupScreenState();
}

class _BillingSetupScreenState extends ConsumerState<BillingSetupScreen> {
  BillSettings? _s;
  bool _printLogo = false;
  bool _hasLogo = false;
  /// False when the server predates Billing Setup — it would silently drop
  /// the settings, so the page says so instead of pretending to save.
  bool _supported = true;
  String? _loadError;
  bool _saving = false;

  final _terms = TextEditingController();
  final _altPhone = TextEditingController();
  final _altPhoneLabel = TextEditingController();
  final _note = TextEditingController();
  final _upiId = TextEditingController();
  final _bank = {for (final k in BillSettings.bankKeys) k: TextEditingController()};

  static final _ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _accountRe = RegExp(r'^[0-9]{6,20}$');
  // Same rule as billSettings.js.
  static final _upiRe = RegExp(r'^[a-zA-Z0-9._-]{2,64}@[a-zA-Z][a-zA-Z0-9.]{1,30}$');

  /// Needed only while the QR is ticked; when filled it must be valid.
  String? get _upiError {
    final v = _upiId.text.trim();
    if (v.isEmpty && !_s!.showUpiQr) return null;
    return _upiRe.hasMatch(v) ? null : context.l10n.storeUpiIdInvalid;
  }

  // Indian mobile, same rule as billSettings.js.
  String? get _altPhoneError {
    final v = _altPhone.text.trim();
    return v.isEmpty || isIndianMobile(v)
        ? null
        : context.l10n.billSetupAltPhoneInvalid;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _terms.dispose();
    _altPhone.dispose();
    _altPhoneLabel.dispose();
    _note.dispose();
    _upiId.dispose();
    for (final c in _bank.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await getBusinessProfile();
      final s = BillSettings.fromJson(p['bill_settings'] as Map?);
      if (!mounted) return;
      setState(() {
        _supported = p.containsKey('bill_settings');
        _s = s;
        _printLogo = p['print_logo'] == true;
        _hasLogo = (p['logo_url'] as String?)?.isNotEmpty ?? false;
        _terms.text = (p['bill_footer_note'] as String?) ?? '';
        _altPhone.text = s.altPhone;
        _altPhoneLabel.text = s.altPhoneLabel;
        _note.text = s.note;
        // The online store's UPI ID, if the shop already set one there.
        _upiId.text = s.upiId.isNotEmpty
            ? s.upiId
            : (p['store_upi_id'] as String?) ?? '';
        for (final k in BillSettings.bankKeys) {
          _bank[k]!.text = s.bank[k] ?? '';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = sanitizeUiErrorMessage(e));
    }
  }

  String? _bankError(String k) {
    final v = _bank[k]!.text.replaceAll(' ', '');
    if (v.isEmpty) return null;
    if (k == 'ifsc' && !_ifscRe.hasMatch(v)) return context.l10n.billSetupIfscInvalid;
    if (k == 'account_no' && !_accountRe.hasMatch(v)) {
      return context.l10n.billSetupAccountNoInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    final s = _s!;
    final l10n = context.l10n;
    if (_altPhoneError != null || _upiError != null) {
      setState(() {});
      return;
    }
    if (s.showBank &&
        (_bank['account_no']!.text.trim().isEmpty ||
            _bankError('account_no') != null ||
            _bankError('ifsc') != null)) {
      setState(() {}); // surface the field errors
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.billSetupBankIncomplete),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _saving = true);
    try {
      final json = s.toJson()
        ..['alt_phone'] = _altPhone.text.trim()
        ..['alt_phone_label'] = _altPhoneLabel.text.trim()
        ..['note'] = _note.text.trim()
        ..['upi_id'] = _upiId.text.trim()
        ..['bank'] = {
          for (final k in BillSettings.bankKeys) k: _bank[k]!.text.trim(),
        };
      final result = await updateBusinessProfile({
        'bill_settings': json,
        'bill_footer_note': _terms.text.trim(),
        if (_hasLogo) 'print_logo': _printLogo,
      });
      // This device prints right away with the new choice; others pick it
      // up from /license on their next open.
      await BillSettings.sync(result);
      if (_hasLogo) {
        await syncBusinessLogo(result['logo_url'] as String?, _printLogo);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.billSetupSaved)));
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(sanitizeUiErrorMessage(e)),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  BillSettings _with(BillSettings s, String key, bool v) {
    final j = s.toJson()..[key] = v;
    return BillSettings.fromJson(j);
  }

  Widget _check(String key, bool value, IconData icon, String title,
      [String? subtitle]) {
    return CheckboxListTile(
      value: value,
      onChanged: _saving ? null : (v) => setState(() => _s = _with(_s!, key, v ?? false)),
      secondary: Icon(icon, color: AppColors.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.space12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _s;
    Widget body;
    if (_loadError != null) {
      body = Center(child: Text(_loadError!));
    } else if (s == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_supported) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Text(l10n.billSetupUnsupported, textAlign: TextAlign.center),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(AppSpacing.space16).copyWith(
            bottom: AppSpacing.space16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space12),
            child: Text(l10n.billSetupIntro,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          _card([
            CheckboxListTile(
              value: _hasLogo && _printLogo,
              onChanged: !_hasLogo || _saving
                  ? null
                  : (v) => setState(() => _printLogo = v ?? false),
              secondary: const Icon(Icons.image_outlined, color: AppColors.primary),
              title: Text(l10n.billSetupLogo),
              subtitle: _hasLogo ? null : Text(l10n.billSetupLogoMissing),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
            _check('show_address', s.showAddress, Icons.location_on_outlined,
                l10n.billSetupAddress),
            _check('show_phone', s.showPhone, Icons.phone_outlined,
                l10n.billSetupPhone),
            if (s.showPhone)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space8),
                // Label + number: prints as "GPay: 98…" ("WhatsApp", …), or
                // just the number when the label is left empty.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: AppTextField(
                        label: l10n.billSetupAltPhoneLabel,
                        hint: l10n.billSetupAltPhoneLabelHint,
                        controller: _altPhoneLabel,
                        maxLength: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space8),
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        label: l10n.billSetupAltPhone,
                        controller: _altPhone,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        errorText: _altPhoneError,
                        prefixIcon: const Icon(Icons.phone_android_outlined,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            _check('show_gstin', s.showGstin, Icons.receipt_long_outlined,
                l10n.billSetupGstin),
            _check('show_fssai', s.showFssai, Icons.verified_outlined,
                l10n.billSetupFssai),
          ]),
          _card([
            _check('show_cashier', s.showCashier, Icons.badge_outlined,
                l10n.billSetupCashier),
            _check('show_customer', s.showCustomer, Icons.person_outline,
                l10n.billSetupCustomer, l10n.billSetupCustomerSubtitle),
            _check('show_tax_summary', s.showTaxSummary, Icons.table_chart_outlined,
                l10n.billSetupTaxSummary, l10n.billSetupTaxSummarySubtitle),
            _check('show_units', s.showUnits, Icons.straighten_outlined,
                l10n.billSetupUnits, l10n.billSetupUnitsSubtitle),
          ]),
          _card([
            _check('show_note', s.showNote, Icons.sticky_note_2_outlined,
                l10n.billSetupNote, l10n.billSetupNoteSubtitle),
            if (s.showNote)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space12),
                child: TextField(
                  controller: _note,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: InputDecoration(
                    labelText: l10n.billSetupNoteText,
                    hintText: l10n.billSetupNoteHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ]),
          _card([
            _check('show_terms', s.showTerms, Icons.gavel_outlined,
                l10n.billSetupTerms),
            if (s.showTerms)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space12),
                child: TextField(
                  controller: _terms,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: l10n.billSetupTermsText,
                    hintText: l10n.billSetupTermsHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ]),
          _card([
            _check('show_warranty_details', s.showWarrantyDetails,
                Icons.verified_outlined, l10n.billSetupWarrantyDetails),
          ]),
          _card([
            _check('show_upi_qr', s.showUpiQr, Icons.qr_code_2,
                l10n.billSetupUpiQr, l10n.billSetupUpiQrSubtitle),
            if (s.showUpiQr)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space12),
                child: AppTextField(
                  label: l10n.storeUpiId,
                  hint: 'shopname@okhdfcbank',
                  controller: _upiId,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 95,
                  errorText: _upiError,
                ),
              ),
          ]),
          _card([
            _check('show_bank', s.showBank, Icons.account_balance_outlined,
                l10n.billSetupBank),
            if (s.showBank)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space12),
                child: Column(children: [
                  for (final (k, label) in [
                    ('account_name', l10n.billSetupBankAccountName),
                    ('account_no', l10n.billSetupBankAccountNo),
                    ('bank_name', l10n.billSetupBankName),
                    ('branch', l10n.billSetupBankBranch),
                    ('ifsc', l10n.billSetupBankIfsc),
                    ('note', l10n.billSetupBankNote),
                  ]) ...[
                    AppTextField(
                      label: label,
                      controller: _bank[k]!,
                      keyboardType:
                          k == 'account_no' ? TextInputType.number : null,
                      maxLength: k == 'ifsc'
                          ? 11
                          : k == 'account_no'
                              ? 20
                              : k == 'note'
                                  ? 200
                                  : 100,
                      capitalizeWords:
                          k == 'account_name' || k == 'bank_name' || k == 'branch',
                      inputFormatters:
                          k == 'ifsc' ? const [UpperCaseTextFormatter()] : null,
                      errorText: _bankError(k),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                  ],
                ]),
              ),
          ]),
          const SizedBox(height: AppSpacing.space8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.commonSave),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(title: Text(l10n.billSetupTitle)),
        Expanded(child: body),
      ]),
    );
  }
}
