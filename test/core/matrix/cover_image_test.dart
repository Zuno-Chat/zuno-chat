import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:zuno/core/matrix/cover_image.dart';

import '../../helpers/pump_until.dart';
import '../../helpers/zuno_app.dart';

void main() {
  Uint8List photo(int width, int height) =>
      img.encodePng(img.Image(width: width, height: height));

  Future<void> pumpMediaImage(WidgetTester tester, MediaImage image) => tester
      .pumpWidget(inZunoApp(SizedBox.square(dimension: 120, child: image)));

  Future<(int, int)> decode(
    WidgetTester tester,
    Uint8List bytes, {
    double? shownAt,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpMediaImage(tester, MediaImage.memory(bytes, shownAt: shownAt));
    final info = await pumpUntilImageLoads(
      tester,
      tester.widget<Image>(find.byType(Image)).image,
    );
    return (info.image.width, info.image.height);
  }

  testWidgets('a wide photo is decoded tall enough to cover its box', (
    tester,
  ) async {
    expect(await decode(tester, photo(1600, 1200), shownAt: 120), (480, 360));
  });

  testWidgets('a tall photo is decoded wide enough to cover its box', (
    tester,
  ) async {
    expect(await decode(tester, photo(1200, 1600), shownAt: 120), (360, 480));
  });

  testWidgets('a panorama is decoded no longer than twice its box', (
    tester,
  ) async {
    expect(await decode(tester, photo(4000, 400), shownAt: 120), (720, 72));
    expect(await decode(tester, photo(400, 4000), shownAt: 120), (72, 720));
  });

  testWidgets('a photo smaller than its box is never enlarged', (tester) async {
    expect(await decode(tester, photo(64, 48), shownAt: 120), (64, 48));
  });

  testWidgets('without a size it covers the width of the screen', (
    tester,
  ) async {
    expect(await decode(tester, photo(1600, 1200)), (1440, 1080));
  });

  testWidgets('a photo that cannot be decoded raises no error', (tester) async {
    await pumpMediaImage(
      tester,
      MediaImage.memory(Uint8List(64), shownAt: 120),
    );

    Object? failure;
    try {
      await pumpUntilImageLoads(
        tester,
        tester.widget<Image>(find.byType(Image)).image,
      );
    } catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
