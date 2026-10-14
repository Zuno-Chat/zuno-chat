import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

export '../../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

Locale resolveAppLocale(List<Locale> preferred) =>
    basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);

AppLocalizations deviceLocalizations() => lookupAppLocalizations(
  resolveAppLocale(PlatformDispatcher.instance.locales),
);

final englishLocalizations = lookupAppLocalizations(const Locale('en'));
