import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n_ext.dart';
import '../theme/app_theme.dart';

/// The legal documents an owner agrees to — the public pages on the website,
/// one source for the sign-up screen, the updated-terms screen and Settings.
/// The server records ONE version for the bundle (backend src/legal.js).
const termsUrl = 'https://vittam.vengurlatech.com/terms';
const acceptableUseUrl = 'https://vittam.vengurlatech.com/acceptable-use';
const privacyUrl = 'https://vittam.vengurlatech.com/privacy';

/// Opens a legal page in the browser; a snackbar if it can't.
Future<void> openLegalUrl(BuildContext context, String url) async {
  bool ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// Consent: ONE checkbox — "I have read and agree to the Terms of Service,
/// Acceptable Use Policy and Privacy Policy" — each document name a link to
/// its page. Starts UNTICKED: a pre-ticked box is weak proof of consent.
/// [onChanged] reports whether it is ticked.
class TermsConsent extends StatefulWidget {
  final ValueChanged<bool> onChanged;
  const TermsConsent({super.key, required this.onChanged});

  @override
  State<TermsConsent> createState() => _TermsConsentState();
}

class _TermsConsentState extends State<TermsConsent> {
  bool _ticked = false;
  late final List<TapGestureRecognizer> _links;

  @override
  void initState() {
    super.initState();
    _links = [termsUrl, acceptableUseUrl, privacyUrl]
        .map((url) => TapGestureRecognizer()..onTap = () => openLegalUrl(context, url))
        .toList();
  }

  @override
  void dispose() {
    for (final r in _links) {
      r.dispose();
    }
    super.dispose();
  }

  void _toggle() {
    setState(() => _ticked = !_ticked);
    widget.onChanged(_ticked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium;
    final link = base?.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: _ticked, onChanged: (_) => _toggle()),
        Expanded(
          child: GestureDetector(
            // Tapping the sentence ticks the box; tapping a document name
            // opens that document instead (the link recognizer wins).
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space12),
              child: Text.rich(
                TextSpan(style: base, children: [
                  TextSpan(text: '${l10n.termsConsentLead} '),
                  TextSpan(text: l10n.termsConsentTos, style: link, recognizer: _links[0]),
                  const TextSpan(text: ', '),
                  TextSpan(text: l10n.termsConsentAup, style: link, recognizer: _links[1]),
                  TextSpan(text: ' ${l10n.termsConsentAnd} '),
                  TextSpan(text: l10n.termsConsentPrivacy, style: link, recognizer: _links[2]),
                  const TextSpan(text: '.'),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
