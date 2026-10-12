import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)` — used as `context.l10n.save`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// A payment mode from the API ('cash', 'upi', … 'split') as display text.
String paymentModeLabel(AppLocalizations l10n, String mode) => switch (mode) {
      'cash' => l10n.paymentCash,
      'upi' => l10n.paymentUpi,
      'card' => l10n.paymentCard,
      'credit' => l10n.paymentCredit,
      'split' => l10n.paymentSplit,
      _ => l10n.paymentOther,
    };
