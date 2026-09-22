import 'package:flutter/material.dart';

import 'zuno_colors.dart';
import 'zuno_motion.dart';

abstract final class ZunoRadius {
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 20.0;
  static const sheet = 28.0;
}

final zunoLightTheme = _theme(_lightScheme, ZunoColors.light);
final zunoDarkTheme = _theme(_darkScheme, ZunoColors.dark);

final _lightScheme = ColorScheme.fromSeed(seedColor: zunoAmber).copyWith(
  surfaceContainerLowest: const Color(0xFFFFFFFF),
  surface: const Color(0xFFFBF8F3),
  surfaceContainerLow: const Color(0xFFF6F2EA),
  surfaceContainer: const Color(0xFFF1ECE3),
  surfaceContainerHigh: const Color(0xFFEBE5DA),
  surfaceContainerHighest: const Color(0xFFE8E2D6),
  onSurface: const Color(0xFF1F1A12),
  onSurfaceVariant: const Color(0xFF696151),
  primary: const Color(0xFF8A5A00),
  onPrimary: const Color(0xFFFFFFFF),
  primaryContainer: zunoAmber,
  onPrimaryContainer: zunoInk,
  secondaryContainer: const Color(0xFFF6EBD6),
  onSecondaryContainer: const Color(0xFF1F1A12),
  error: const Color(0xFFBA1A1A),
  onError: const Color(0xFFFFFFFF),
  outline: const Color(0xFF8F8672),
  outlineVariant: const Color(0xFFE7E0D2),
  inverseSurface: const Color(0xFF2B2620),
  onInverseSurface: const Color(0xFFF3EEE5),
  surfaceTint: Colors.transparent,
);

final _darkScheme =
    ColorScheme.fromSeed(
      seedColor: zunoAmber,
      brightness: Brightness.dark,
    ).copyWith(
      surfaceContainerLowest: const Color(0xFF191612),
      surface: const Color(0xFF201D18),
      surfaceContainerLow: const Color(0xFF29251F),
      surfaceContainer: const Color(0xFF332F27),
      surfaceContainerHigh: const Color(0xFF403B31),
      surfaceContainerHighest: const Color(0xFF4B453A),
      onSurface: const Color(0xFFF5EFE6),
      onSurfaceVariant: const Color(0xFFBDB4A4),
      primary: const Color(0xFFF2B95E),
      onPrimary: zunoInk,
      primaryContainer: zunoAmber,
      onPrimaryContainer: zunoInk,
      secondaryContainer: const Color(0xFF453619),
      onSecondaryContainer: const Color(0xFFF5EFE6),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      outline: const Color(0xFF968C79),
      outlineVariant: const Color(0xFF555042),
      inverseSurface: const Color(0xFFEDE6DA),
      onInverseSurface: const Color(0xFF2B2620),
      surfaceTint: Colors.transparent,
    );

const _textTheme = TextTheme(
  headlineMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  ),
  titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  ),
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.35),
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
);

BorderRadius _rounded(double radius) => BorderRadius.circular(radius);

UnderlineInputBorder _inputBorder(BorderSide side) => UnderlineInputBorder(
  borderRadius: _rounded(ZunoRadius.medium),
  borderSide: side,
);

ThemeData _theme(ColorScheme scheme, ZunoColors zuno) {
  final text = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: _textTheme,
  ).textTheme;

  Color? whenEnabled(Set<WidgetState> states, Color on, Color off) {
    if (states.contains(WidgetState.disabled)) return null;
    return states.contains(WidgetState.selected) ? on : off;
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: _textTheme,
    extensions: [zuno],
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: ZunoSlideTransitionsBuilder()},
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: _rounded(ZunoRadius.medium)),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.primaryContainer,
      textColor: scheme.onPrimaryContainer,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => whenEnabled(
          states,
          scheme.primaryContainer,
          scheme.surfaceContainerHighest,
        ),
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            whenEnabled(states, scheme.onPrimaryContainer, scheme.outline),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => whenEnabled(states, Colors.transparent, scheme.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: _inputBorder(BorderSide.none),
      enabledBorder: _inputBorder(BorderSide.none),
      disabledBorder: _inputBorder(BorderSide.none),
      focusedBorder: _inputBorder(BorderSide(color: scheme.primary, width: 2)),
      errorBorder: _inputBorder(BorderSide(color: scheme.error)),
      focusedErrorBorder: _inputBorder(
        BorderSide(color: scheme.error, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: _rounded(ZunoRadius.sheet)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZunoRadius.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: _rounded(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}
