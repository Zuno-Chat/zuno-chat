import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'app_locale.dart';

export '../../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

AppLocalizations deviceLocalizations() =>
    lookupAppLocalizations(AppLocale.instance.value);

final englishLocalizations = lookupAppLocalizations(const Locale('en'));
