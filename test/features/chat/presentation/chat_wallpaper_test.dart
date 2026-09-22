import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/chat_wallpaper.dart';

void main() {
  Future<void> pump(WidgetTester tester, ThemeData theme) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: const Scaffold(body: Stack(children: [ChatWallpaperBackground()])),
    ),
  );

  Image wallpaper(WidgetTester tester) => tester.widget<Image>(
    find.descendant(
      of: find.byType(ChatWallpaperBackground),
      matching: find.byType(Image),
    ),
  );

  test('the tile ships in three densities, declared in the pubspec', () {
    for (final path in [
      'assets/wallpaper/chat_tile.png',
      'assets/wallpaper/2.0x/chat_tile.png',
      'assets/wallpaper/3.0x/chat_tile.png',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/wallpaper/'),
    );
  });

  testWidgets('one image, repeated at its own size, fills the chat', (
    tester,
  ) async {
    await pump(tester, zunoLightTheme);

    final image = wallpaper(tester);
    expect((image.image as AssetImage).assetName, chatWallpaperAsset);
    expect(image.repeat, ImageRepeat.repeat);
    expect(image.fit, BoxFit.none);
    expect(image.alignment, Alignment.topLeft);
    expect(image.filterQuality, FilterQuality.low);
    expect(
      tester.getSize(find.byType(ChatWallpaperBackground)),
      tester.getSize(find.byType(Scaffold)),
    );
    expect(
      find.descendant(
        of: find.byType(ChatWallpaperBackground),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  for (final theme in [zunoLightTheme, zunoDarkTheme]) {
    testWidgets('the white tile is tinted faintly with the text color, '
        '${theme.brightness.name}', (tester) async {
      await pump(tester, theme);

      final image = wallpaper(tester);
      final tint = image.color!;
      expect(image.colorBlendMode, BlendMode.srcIn);
      expect(tint.withValues(alpha: 1), theme.colorScheme.onSurface);
      expect(tint.a, inInclusiveRange(0.04, 0.12));
    });
  }

  testWidgets('it is decoration: nothing for a screen reader, and it repaints '
      'apart from the messages', (tester) async {
    await pump(tester, zunoLightTheme);

    expect(wallpaper(tester).excludeFromSemantics, isTrue);
    expect(
      find.descendant(
        of: find.byType(ChatWallpaperBackground),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });
}
