import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)` — used as `context.l10n.save`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
