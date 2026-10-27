import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../services/license_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/terms_consent.dart';
import 'login_screen.dart';

/// Full page for an existing owner who has not accepted the current legal
/// terms (GET /license terms_required; pushed by main_shell). It cannot be
/// backed out of: the only ways on are Agree — recorded on the server, which
/// alone closes the page — or Log out.
///
/// Layout: the documents scroll at the top; the consent checkbox, Agree and
/// Log out stay pinned to the bottom so they are always in reach.
class TermsAcceptScreen extends ConsumerStatefulWidget {
  final String termsVersion;
  const TermsAcceptScreen({super.key, required this.termsVersion});

  @override
  ConsumerState<TermsAcceptScreen> createState() => _TermsAcceptScreenState();
}

class _TermsAcceptScreenState extends ConsumerState<TermsAcceptScreen> {
  bool _allAccepted = false;
  bool _saving = false;
  String? _error;

  Future<void> _agree() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await acceptTerms(widget.termsVersion);
      LicenseService.instance.termsRequired.value = false;
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      // 409: the terms changed while this page was open — the server says so.
      if (mounted) setState(() => _error = e.serverMessage ?? context.l10n.termsSaveFailed);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.termsSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Same steps as Settings → Logout.
  Future<void> _logout() async {
    await RealtimeService.instance.stop();
    ref.invalidate(openDraftsProvider);
    await ref.read(sessionProvider.notifier).clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final docs = [
      (Icons.description_outlined, l10n.termsConsentTos, l10n.settingsTermsSubtitle, termsUrl),
      (Icons.gavel_outlined, l10n.termsConsentAup, l10n.settingsAupSubtitle, acceptableUseUrl),
      (Icons.privacy_tip_outlined, l10n.termsConsentPrivacy, l10n.settingsPrivacyPolicySubtitle, privacyUrl),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Scrolling content ──────────────────────────────────────
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.space24,
                          AppSpacing.space48, AppSpacing.space24, AppSpacing.space24),
                      children: [
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_user_outlined,
                                size: 36, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space24),
                        Text(l10n.termsUpdatedTitle,
                            textAlign: TextAlign.center,
                            style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: AppSpacing.space12),
                        Text(l10n.termsUpdatedBody,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                                color: AppColors.textSecondary, height: 1.5)),
                        const SizedBox(height: AppSpacing.space12),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space12, vertical: AppSpacing.space4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(l10n.termsUpdatedVersion(widget.termsVersion),
                                style: text.labelSmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space32),
                        for (final d in docs) ...[
                          _DocCard(icon: d.$1, title: d.$2, subtitle: d.$3,
                              onTap: () => openLegalUrl(context, d.$4)),
                          const SizedBox(height: AppSpacing.space12),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ── Pinned bottom panel ────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: const Border(top: BorderSide(color: AppColors.border)),
                  boxShadow: AppShadow.medium,
                ),
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                            AppSpacing.space12, AppSpacing.space16, AppSpacing.space8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TermsConsent(
                                onChanged: (v) => setState(() => _allAccepted = v)),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.space8),
                                child: Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: text.bodySmall?.copyWith(color: AppColors.error)),
                              ),
                            const SizedBox(height: AppSpacing.space12),
                            PrimaryButton(
                              text: l10n.termsAgree,
                              icon: Icons.check_circle_outline,
                              onPressed: _allAccepted && !_saving ? _agree : null,
                              isLoading: _saving,
                            ),
                            TextButton(
                              onPressed: _saving ? null : _logout,
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary),
                              child: Text(l10n.logout),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One legal document: icon, name, one-line summary, opens the full text.
class _DocCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _DocCard(
      {required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
