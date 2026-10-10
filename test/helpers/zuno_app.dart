import 'package:flutter/material.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

Widget inZunoApp(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? zunoLightTheme,
  home: Scaffold(body: Center(child: child)),
);
