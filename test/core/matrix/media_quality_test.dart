import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/media_quality.dart';

void main() {
  group('pickerImageLimits', () {
    test('with a native resizer the picker hands over the original', () {
      for (final reduce in [true, false]) {
        expect(
          pickerImageLimits(nativeImageResize: true, reduceMediaSize: reduce),
          (maxDimension: null, quality: null),
        );
      }
    });

    test('without one the picker shrinks to the send size and quality', () {
      expect(
        pickerImageLimits(nativeImageResize: false, reduceMediaSize: false),
        (maxDimension: 1080.0, quality: 85),
      );
      expect(
        pickerImageLimits(nativeImageResize: false, reduceMediaSize: true),
        (maxDimension: 720.0, quality: 75),
      );
    });
  });

  group('scaledToFit', () {
    test('shrinks a landscape source down, preserving aspect ratio', () {
      final result = scaledToFit(width: 1920, height: 1080, maxLongEdge: 720);
      expect(result.width, 720);
      expect(result.height, 404);
    });

    test('shrinks a portrait source down by height, not width', () {
      final result = scaledToFit(width: 1080, height: 1920, maxLongEdge: 480);
      expect(result.height, 480);
      expect(result.width, 270);
    });

    test('never scales up a source already smaller than the cap', () {
      final result = scaledToFit(width: 320, height: 240, maxLongEdge: 1080);
      expect(result, (width: 320, height: 240));
    });

    test('rounds an odd result down to the nearest even number', () {
      final result = scaledToFit(width: 1333, height: 999, maxLongEdge: 721);
      expect(result, (width: 720, height: 540));
    });

    test('a square source scales both dimensions equally', () {
      final result = scaledToFit(width: 2000, height: 2000, maxLongEdge: 500);
      expect(result, (width: 500, height: 500));
    });

    test(
      'degenerate zero dimensions are returned unchanged rather than throwing',
      () {
        final result = scaledToFit(width: 0, height: 0, maxLongEdge: 720);
        expect(result, (width: 0, height: 0));
      },
    );
  });

  group('encoderTarget', () {
    test('a portrait video stored sideways is sized in its stored shape', () {
      expect(encoderTarget(width: 404, height: 720, rotated: true), (
        width: 720,
        height: 404,
      ));
    });

    test('a portrait video stored upright keeps its shape', () {
      expect(encoderTarget(width: 332, height: 720, rotated: false), (
        width: 332,
        height: 720,
      ));
    });

    test('a landscape video stored sideways is sized in its stored shape', () {
      expect(encoderTarget(width: 720, height: 404, rotated: true), (
        width: 404,
        height: 720,
      ));
    });

    test('without knowing how it is stored, a portrait video is taken as '
        'stored sideways', () {
      expect(encoderTarget(width: 404, height: 720, rotated: null), (
        width: 720,
        height: 404,
      ));
      expect(encoderTarget(width: 720, height: 404, rotated: null), (
        width: 720,
        height: 404,
      ));
    });

    test('without a size there is no target', () {
      expect(encoderTarget(width: null, height: 720, rotated: true), isNull);
    });
  });
}
