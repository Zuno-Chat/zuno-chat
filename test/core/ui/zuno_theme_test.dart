import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

import '../../helpers/contrast.dart';

void main() {
  final themes = {'light': zunoLightTheme, 'dark': zunoDarkTheme};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    final scheme = theme.colorScheme;
    final zuno = theme.extension<ZunoColors>()!;

    test('$name: every text color is readable on every surface', () {
      final surfaces = {
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surface': scheme.surface,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'secondaryContainer': scheme.secondaryContainer,
      };
      final texts = {
        'onSurface': scheme.onSurface,
        'onSurfaceVariant': scheme.onSurfaceVariant,
        'primary': scheme.primary,
        'error': scheme.error,
        'success': zuno.success,
      };
      for (final text in texts.entries) {
        for (final surface in surfaces.entries) {
          expect(
            contrastRatio(text.value, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: '${text.key} on ${surface.key}',
          );
        }
      }
    });

    test('$name: filled pairs are readable', () {
      expect(
        contrastRatio(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(scheme.onSecondaryContainer, scheme.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(scheme.onInverseSurface, scheme.inverseSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('$name: amber is the fill, depth is tonal, push slides', () {
      expect(scheme.primaryContainer, zunoAmber);
      expect(scheme.surfaceTint, Colors.transparent);
      expect(
        theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
        zunoAmber,
      );
      expect(theme.floatingActionButtonTheme.backgroundColor, zunoAmber);
      expect(theme.floatingActionButtonTheme.elevation, 0);
      expect(theme.badgeTheme.backgroundColor, zunoAmber);
      expect(theme.splashFactory, InkRipple.splashFactory);
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<ZunoSlideTransitionsBuilder>(),
      );
    });

    test('$name: only weights every Roboto build has', () {
      final text = theme.textTheme;
      final styles = [
        text.headlineMedium,
        text.titleLarge,
        text.titleMedium,
        text.bodyLarge,
        text.bodyMedium,
        text.labelLarge,
        text.labelMedium,
      ];
      for (final style in styles) {
        expect([
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w700,
        ], contains(style!.fontWeight));
      }
      expect(text.headlineMedium!.fontSize, 28);
      expect(text.titleLarge!.fontSize, 20);
      expect(text.bodyLarge!.height, 1.35);
    });

    test('$name: list subtitles stay muted, titles stay ink', () {
      final tiles = theme.listTileTheme;
      expect(tiles.titleTextStyle!.color, scheme.onSurface);
      expect(tiles.titleTextStyle!.fontWeight, FontWeight.w500);
      expect(tiles.subtitleTextStyle!.color, scheme.onSurfaceVariant);
    });

    test('$name: the app bar title still follows a local foreground', () {
      expect(theme.appBarTheme.titleTextStyle, isNull);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
    });

    test('$name: inputs keep one border type in every state', () {
      final inputs = theme.inputDecorationTheme;
      final borders = [
        inputs.border,
        inputs.enabledBorder,
        inputs.disabledBorder,
        inputs.focusedBorder,
        inputs.errorBorder,
        inputs.focusedErrorBorder,
      ];
      for (final border in borders) {
        expect(border, isA<UnderlineInputBorder>());
      }
      expect(inputs.disabledBorder!.borderSide, BorderSide.none);
      expect(inputs.focusedBorder!.borderSide.width, 2);
    });

    test('$name: divider is a hairline with no layout change', () {
      expect(theme.dividerTheme.space, isNull);
      expect(theme.dividerTheme.color, scheme.outlineVariant);
    });
  }

  test('each theme carries its own bubble colors', () {
    expect(zunoLightTheme.extension<ZunoColors>(), same(ZunoColors.light));
    expect(zunoDarkTheme.extension<ZunoColors>(), same(ZunoColors.dark));
    expect(zunoLightTheme.brightness, Brightness.light);
    expect(zunoDarkTheme.brightness, Brightness.dark);
  });

  test('a disabled switch falls back to the Material default', () {
    final track = zunoLightTheme.switchTheme.trackColor!;
    expect(track.resolve({WidgetState.disabled}), isNull);
    expect(track.resolve({WidgetState.selected}), zunoAmber);
  });
}
