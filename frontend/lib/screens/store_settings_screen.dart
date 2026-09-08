import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../services/notification_service.dart';
import '../services/table_qr_image.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../utils/jpeg_compress.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import 'online_orders_screen.dart';

/// Owner-only setup for the online store: the master switch, the shareable
/// link, how customers receive their order, and what they pay up front.
///
/// Everything here writes through the existing business-profile endpoint, so a
/// change is live on the public page the moment it saves — there is no publish
/// step and no second source of truth.
class StoreSettingsScreen extends ConsumerStatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  ConsumerState<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends ConsumerState<StoreSettingsScreen> {
  final _picker = ImagePicker();
  final _deliveryController = TextEditingController();
  final _advanceController = TextEditingController();
  final _upiController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _enabled = false;
  String? _storeToken;
  bool _delivery = false;
  bool _paymentRequired = false;
  String? _paymentQrUrl;

  // ── Editing the store link ────────────────────────────────────────────────
  // The card is read-only until the owner taps "Edit link"; the field then
  // checks availability as they type so they learn a link is taken before
  // committing to it rather than on save.
  final _linkController = TextEditingController();
  bool _editingLink = false;
  bool _checkingLink = false;
  /// null while unchecked/checking; true = free, false = rejected ([_linkError]
  /// says why).
  bool? _linkAvailable;
  String? _linkError;
  /// Guards against a slow earlier check landing after a later one and
  /// overwriting its verdict with a stale answer.
  int _linkCheckSeq = 0;
  Timer? _linkDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _linkDebounce?.cancel();
    _linkController.dispose();
    _deliveryController.dispose();
    _advanceController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await getBusinessProfile();
      if (!mounted) return;
      setState(() {
        _enabled = p['store_enabled'] == true;
        _storeToken = p['store_token'] as String?;
        _delivery = p['store_delivery_enabled'] == true;
        _paymentRequired = p['store_payment_required'] == true;
        _paymentQrUrl = p['store_payment_qr_url'] as String?;
        _deliveryController.text = _trimNumber(p['store_delivery_charge']);
        _advanceController.text = _trimNumber(p['store_advance_percent']);
        _upiController.text = (p['store_upi_id'] as String?) ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// 30.00 reads as noise in a text field the owner types into; show 30.
  String _trimNumber(dynamic v) {
    final d = double.tryParse('${v ?? 0}') ?? 0;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  String get _link => _storeToken == null ? '' : storeUrl(_storeToken!);

  // ── Editing the store link ────────────────────────────────────────────────

  void _startEditingLink() {
    setState(() {
      _editingLink = true;
      _linkController.text = _storeToken ?? '';
      // The current link is trivially "available" to its own shop, but there is
      // nothing to save until it actually changes, so start with no verdict.
      _linkAvailable = null;
      _linkError = null;
      _checkingLink = false;
    });
  }

  void _cancelEditingLink() {
    _linkDebounce?.cancel();
    setState(() {
      _editingLink = false;
      _linkError = null;
      _linkAvailable = null;
      _checkingLink = false;
    });
  }

  /// Ask the server whether what has been typed is usable, a beat after typing
  /// stops. Debounced so a 12-character link is one request, not twelve.
  void _onLinkChanged(String value) {
    _linkDebounce?.cancel();
    final slug = value.trim();
    // Unchanged from what is already saved: nothing to check, nothing to save.
    if (slug == (_storeToken ?? '')) {
      setState(() {
        _checkingLink = false;
        _linkAvailable = null;
        _linkError = null;
      });
      return;
    }
    setState(() {
      _checkingLink = true;
      _linkAvailable = null;
      _linkError = null;
    });
    _linkDebounce = Timer(const Duration(milliseconds: 400), () async {
      final seq = ++_linkCheckSeq;
      try {
        final r = await checkStoreLink(slug);
        // A later keystroke already started its own check — drop this answer
        // rather than letting it overwrite a fresher verdict.
        if (!mounted || seq != _linkCheckSeq) return;
        setState(() {
          _checkingLink = false;
          _linkAvailable = r.available;
          _linkError = r.error;
        });
      } catch (e) {
        if (!mounted || seq != _linkCheckSeq) return;
        setState(() {
          _checkingLink = false;
          _linkAvailable = null;
          _linkError = sanitizeUiErrorMessage(e);
        });
      }
    });
  }

  /// Claim the typed link. The server re-checks it — the availability probe
  /// above is advisory, and someone else can take a link in between — so a
  /// rejection here is expected, not exceptional.
  Future<void> _saveLink() async {
    final l10n = context.l10n;
    final slug = _linkController.text.trim();
    if (slug.isEmpty || slug == _storeToken) return _cancelEditingLink();

    setState(() => _saving = true);
    try {
      final updated = await updateBusinessProfile({'store_token': slug});
      if (!mounted) return;
      setState(() {
        _storeToken = (updated['store_token'] as String?) ?? _storeToken;
        _editingLink = false;
        _linkError = null;
        _linkAvailable = null;
      });
      _snack(l10n.storeLinkUpdated);
    } on ApiException catch (e) {
      // Stay in edit mode with the reason under the field: the owner needs to
      // pick a different link, and bouncing them out would lose what they typed.
      if (mounted) setState(() => _linkError = sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Full URL for the stored QR path — the server returns it root-relative.
  String? get _qrImageUrl {
    if (_paymentQrUrl == null) return null;
    var host = baseUrl;
    if (host.endsWith('/api')) host = host.substring(0, host.length - 4);
    return '$host$_paymentQrUrl';
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      final updated = await updateBusinessProfile(patch);
      if (!mounted) return;
      setState(() {
        _enabled = updated['store_enabled'] == true;
        _storeToken = (updated['store_token'] as String?) ?? _storeToken;
        _delivery = updated['store_delivery_enabled'] == true;
        _paymentRequired = updated['store_payment_required'] == true;
      });
      // Keep the cached session in step so the shell starts (or stops) polling
      // the order queue right away, instead of at the next login.
      if (patch.containsKey('store_enabled')) {
        await updateStoreEnabled(_enabled);
        await ref.read(sessionProvider.notifier).refresh();
        // Switching the store on is the only moment a notification prompt makes
        // sense to the owner — orders will now arrive when nobody is looking.
        if (_enabled) await NotificationService.instance.requestPermission();
      }
      if (mounted) _snack(l10n.storeSaved);
    } on ApiException catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
      await _load(); // put the switches back to what the server actually has
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Persist the two number fields together — they are typed, not toggled, so
  /// they save on focus loss rather than on every keystroke.
  Future<void> _saveNumbers() async {
    final l10n = context.l10n;
    final charge = double.tryParse(_deliveryController.text.trim()) ?? 0;
    final advance = double.tryParse(_advanceController.text.trim()) ?? 0;
    if (advance < 0 || advance > 100) {
      _snack(l10n.storeInvalidPercent, isError: true);
      return;
    }
    await _save({
      'store_delivery_charge': charge,
      'store_advance_percent': advance,
    });
  }

  /// Saved on focus loss like the other typed settings. Validated here as well
  /// as on the server so a typo is caught before it reaches a customer's phone
  /// as a button opening their UPI app on an address that does not exist.
  Future<void> _saveUpiId() async {
    final value = _upiController.text.trim();
    if (value.isNotEmpty &&
        !RegExp(r'^[a-zA-Z0-9._-]{2,64}@[a-zA-Z][a-zA-Z0-9.]{1,30}$').hasMatch(value)) {
      _snack(context.l10n.storeUpiIdInvalid, isError: true);
      return;
    }
    await _save({'store_upi_id': value});
  }

  Future<void> _pickQr(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
          source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
    } catch (_) {
      if (mounted) _snack(context.l10n.errorSomethingWentWrong, isError: true);
      return;
    }
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final raw = await picked.readAsBytes();
      final jpeg = await compressToJpeg(raw);
      final url = await uploadStorePaymentQr(jpeg);
      if (!mounted) return;
      setState(() => _paymentQrUrl = url);
      _snack(context.l10n.storeSaved);
    } catch (e) {
      if (mounted) _snack(context.l10n.errorSomethingWentWrong, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeQr() async {
    setState(() => _saving = true);
    try {
      await deleteStorePaymentQr();
      if (mounted) setState(() => _paymentQrUrl = null);
    } catch (e) {
      if (mounted) _snack(context.l10n.errorSomethingWentWrong, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Share the store link as a printable QR — the same renderer the table
  /// stickers use, so a shop can put one on the counter or in a status update.
  Future<void> _shareQr() async {
    try {
      final png = await TableQrImage.renderPng(
          data: _link, label: ref.read(businessNameProvider), pixelSize: 800);
      await Share.shareXFiles(
        [XFile.fromData(png, name: 'store_qr.png', mimeType: 'image/png')],
        text: _link,
      );
    } catch (_) {
      if (mounted) _snack(context.l10n.errorSomethingWentWrong, isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(title: Text(l10n.storeTitle)),
        Expanded(child: _body(l10n)),
      ]),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppErrorWidget(error: _error!, onRetry: _load);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space16),
      children: [
        _card(SwitchListTile(
          value: _enabled,
          onChanged: _saving ? null : (v) => _save({'store_enabled': v}),
          secondary: const Icon(Icons.storefront_outlined, color: AppColors.primary),
          title: Text(l10n.storeEnable,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(l10n.storeEnableSubtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        )),

        // Everything below only means something once the store is on.
        if (_enabled) ...[
          const SizedBox(height: AppSpacing.space16),
          _linkCard(l10n),

          const SizedBox(height: AppSpacing.space16),
          _card(ListTile(
            leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
            title: Text(l10n.storeOrdersLink,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l10n.storeOrdersLinkSubtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OnlineOrdersScreen())),
          )),

          const SizedBox(height: AppSpacing.space24),
          _sectionLabel(l10n.storeFulfilmentSection),
          _card(Column(children: [
            // Pickup has no switch: a customer can always walk in and collect,
            // so the only thing a shop actually decides is whether it delivers.
            ListTile(
              leading: const Icon(Icons.storefront_outlined,
                  color: AppColors.textSecondary),
              title: Text(l10n.storePickup),
              subtitle: Text(l10n.storePickupAlways,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: _delivery,
              onChanged:
                  _saving ? null : (v) => _save({'store_delivery_enabled': v}),
              title: Text(l10n.storeDelivery),
              subtitle: Text(l10n.storeDeliverySubtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
            // A delivery charge with delivery switched off would never be
            // applied, so it is not shown.
            if (_delivery)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
                    AppSpacing.space16, AppSpacing.space16),
                child: _numberField(
                  controller: _deliveryController,
                  label: l10n.storeDeliveryCharge,
                  helper: l10n.storeDeliveryChargeHint,
                  prefix: '₹',
                ),
              ),
          ])),

          const SizedBox(height: AppSpacing.space24),
          _sectionLabel(l10n.storePaymentSection),
          _card(Column(children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space16),
              child: _numberField(
                controller: _advanceController,
                label: l10n.storeAdvancePercent,
                helper: l10n.storeAdvancePercentHint,
                suffix: '%',
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: _paymentRequired,
              onChanged: _saving
                  ? null
                  : (v) => _save({'store_payment_required': v}),
              title: Text(l10n.storePaymentRequired),
              subtitle: Text(l10n.storePaymentRequiredSubtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ])),

          const SizedBox(height: AppSpacing.space16),
          _upiCard(l10n),

          const SizedBox(height: AppSpacing.space16),
          _paymentQrCard(l10n),
          const SizedBox(height: AppSpacing.space32),
        ],
      ],
    );
  }

  Widget _linkCard(AppLocalizations l10n) => _card(Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.storeLinkTitle,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: AppSpacing.space4),
            Text(l10n.storeLinkHint,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.space12),
            if (_editingLink) ..._linkEditor(l10n) else ..._linkDisplay(l10n),
          ],
        ),
      ));

  /// The settled state: the link, and what you can do with it.
  List<Widget> _linkDisplay(AppLocalizations l10n) => [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.space12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: SelectableText(_link,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        ),
        const SizedBox(height: AppSpacing.space12),
        Row(children: [
          Expanded(
            child: SecondaryButton(
              text: l10n.storeCopyLink,
              icon: Icons.copy_outlined,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _link));
                if (mounted) _snack(l10n.storeLinkCopied);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.space8),
          Expanded(
            child: SecondaryButton(
              text: l10n.storeShareQr,
              icon: Icons.qr_code_2,
              onPressed: _shareQr,
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.space8),
        // Deliberately quieter than Copy/Share: changing the link is the rare
        // action here, and the destructive one.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving ? null : _startEditingLink,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l10n.storeEditLink),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ];

  /// The editing state: the fixed host, then the part the owner owns.
  List<Widget> _linkEditor(AppLocalizations l10n) {
    final slug = _linkController.text.trim();
    final changed = slug.isNotEmpty && slug != (_storeToken ?? '');
    // Only offer Save once the server has actually said yes. A link that has
    // not been checked (or is mid-check) is not something to commit to.
    final canSave = changed && _linkAvailable == true && !_checkingLink && !_saving;

    return [
      // The host is not editable, so showing it as a prefix keeps the field
      // about the one part the owner chooses.
      Text('$storeBaseUrl/',
          style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppColors.textSecondary)),
      const SizedBox(height: AppSpacing.space4),
      TextField(
        controller: _linkController,
        autofocus: true,
        enabled: !_saving,
        // Lowercase as they type rather than rejecting it afterwards. Typing
        // "Big Bazaar" would otherwise fail on the capital B first and the
        // space only on the retry — two errors for one obvious intent. Case is
        // the one rule with a single unambiguous fix, so just apply it.
        inputFormatters: [
          TextInputFormatter.withFunction((_, next) => next.copyWith(
              text: next.text.toLowerCase())),
        ],
        onChanged: (v) => setState(() => _onLinkChanged(v)),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) { if (canSave) _saveLink(); },
        style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: l10n.storeLinkLabel,
          helperText: l10n.storeLinkEditHint,
          helperMaxLines: 3,
          errorText: _linkError,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _linkSuffix(),
        ),
      ),
      if (_linkAvailable == true) ...[
        const SizedBox(height: AppSpacing.space8),
        Row(children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: AppColors.success),
          const SizedBox(width: AppSpacing.space4),
          Text(l10n.storeLinkAvailable,
              style: const TextStyle(fontSize: 12, color: AppColors.success)),
        ]),
      ],
      // Stated plainly rather than buried in a confirm dialog: the owner is
      // about to break every QR poster already printed with the old link.
      if (changed) ...[
        const SizedBox(height: AppSpacing.space8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_outlined,
              size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Text(l10n.storeLinkChangeWarning,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
        ]),
      ],
      const SizedBox(height: AppSpacing.space12),
      Row(children: [
        Expanded(
          child: SecondaryButton(
            text: l10n.storeLinkCancel,
            onPressed: _saving ? null : _cancelEditingLink,
          ),
        ),
        const SizedBox(width: AppSpacing.space8),
        Expanded(
          child: PrimaryButton(
            text: l10n.storeLinkSave,
            onPressed: canSave ? _saveLink : null,
          ),
        ),
      ]),
    ];
  }

  /// In-field status: spinner while checking, tick when free. Failures show as
  /// the field's own errorText instead, which reads better than an icon.
  Widget? _linkSuffix() {
    if (_checkingLink) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_linkAvailable == true) {
      return const Icon(Icons.check_circle, color: AppColors.success, size: 20);
    }
    return null;
  }

  /// The UPI ID is what turns the payment step from "scan this and type the
  /// amount yourself" into one tap, so it sits ABOVE the QR — the QR is now the
  /// fallback for iOS, desktop, and anyone scanning from a second device.
  Widget _upiCard(AppLocalizations l10n) => _card(Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Focus(
          onFocusChange: (hasFocus) { if (!hasFocus) _saveUpiId(); },
          child: TextField(
            controller: _upiController,
            enabled: !_saving,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.storeUpiId,
              helperText: l10n.storeUpiIdHint,
              helperMaxLines: 4,
              prefixIcon: const Icon(Icons.account_balance_outlined),
            ),
          ),
        ),
      ));

  Widget _paymentQrCard(AppLocalizations l10n) => _card(Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.storePaymentQr,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: AppSpacing.space4),
            Text(l10n.storePaymentQrHint,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.space12),
            if (_qrImageUrl != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: Image.network(_qrImageUrl!,
                      width: 180, height: 180, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 64)),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Text(l10n.storeQrNeeded,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              ),
            const SizedBox(height: AppSpacing.space12),
            Row(children: [
              Expanded(
                child: SecondaryButton(
                  text: _qrImageUrl == null ? l10n.storeUploadQr : l10n.storeReplaceQr,
                  icon: Icons.upload_outlined,
                  onPressed: _saving ? null : () => _pickQr(ImageSource.gallery),
                ),
              ),
              if (_qrImageUrl != null) ...[
                const SizedBox(width: AppSpacing.space8),
                Expanded(
                  child: SecondaryButton(
                    text: l10n.storeRemoveQr,
                    icon: Icons.delete_outline,
                    onPressed: _saving ? null : _removeQr,
                  ),
                ),
              ],
            ]),
          ],
        ),
      ));

  /// A number input that saves when it loses focus — the owner types a value
  /// and taps away, which is how every other numeric setting in this app works.
  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String helper,
    String? prefix,
    String? suffix,
  }) =>
      Focus(
        onFocusChange: (hasFocus) { if (!hasFocus) _saveNumbers(); },
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 3,
            prefixText: prefix,
            suffixText: suffix,
          ),
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space8, left: AppSpacing.space4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
      );

  Widget _card(Widget child) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}
