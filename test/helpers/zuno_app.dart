import 'package:flutter/material.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

Widget inZunoApp(Widget child, {ThemeData? theme}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: theme ?? zunoLightTheme,
  home: Scaffold(body: Center(child: child)),
);
