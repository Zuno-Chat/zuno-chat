import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:zuno/core/matrix/native_image_resizer.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/image');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final input = Uint8List.fromList([1, 2, 3]);
  final output = Uint8List.fromList([9, 8]);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('resize sends the bytes and limits, and parses the reply', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {
        'bytes': output,
        'width': 1080,
        'height': 810,
        'mimeType': 'image/jpeg',
      };
    });
    final result = await NativeImageResizer.forTest().resize(
      input,
      maxDimension: 1080,
      quality: 85,
    );
    expect(received!.method, 'resize');
    expect(received!.arguments, {
      'bytes': input,
      'maxDimension': 1080,
      'quality': 85,
    });
    expect(result!.bytes, output);
    expect(result.width, 1080);
    expect(result.height, 810);
    expect(result.mimeType, 'image/jpeg');
  });

  test('a null reply means the image could not be decoded', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(
      await NativeImageResizer.forTest().resize(
        input,
        maxDimension: 1080,
        quality: 85,
      ),
      isNull,
    );
  });

  test('a malformed reply is treated as a failure', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {'bytes': output, 'width': '1080'},
    );
    expect(
      await NativeImageResizer.forTest().resize(
        input,
        maxDimension: 1080,
        quality: 85,
      ),
      isNull,
    );
  });

  test('a native error is reported as a failure, not thrown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'decode');
    });
    expect(
      await NativeImageResizer.forTest().resize(
        input,
        maxDimension: 1080,
        quality: 85,
      ),
      isNull,
    );
  });

  test('with android capabilities the resize goes native', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'bytes': output,
        'width': 1080,
        'height': 810,
        'mimeType': 'image/jpeg',
      };
    });
    final result = await NativeImageResizer.forTest(
      capabilities: capabilitiesFor(AppPlatform.android),
    ).resize(input, maxDimension: 1080, quality: 85);
    expect(calls.single.method, 'resize');
    expect(result!.bytes, output);
  });

  group('without native resizing', () {
    late List<MethodCall> calls;
    final resizer = NativeImageResizer.forTest(
      capabilities: capabilitiesFor(AppPlatform.ios),
    );

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    });

    Future<ResizedImage?> resize(Uint8List bytes) =>
        resizer.resize(bytes, maxDimension: 1080, quality: 85);

    test('a JPEG comes back untouched, with its size and type', () async {
      final jpeg = img.encodeJpg(img.Image(width: 1600, height: 1200));
      final result = await resize(jpeg);
      expect(calls, isEmpty);
      expect(result!.bytes, jpeg);
      expect(result.width, 1600);
      expect(result.height, 1200);
      expect(result.mimeType, 'image/jpeg');
    });

    test('a quarter-turned JPEG reports its upright size', () async {
      final turned = img.Image(width: 40, height: 30)
        ..exif.imageIfd.orientation = 6;
      final result = await resize(img.encodeJpg(turned));
      expect(result!.width, 30);
      expect(result.height, 40);
    });

    test('PNG and GIF keep their own type', () async {
      final png = await resize(img.encodePng(img.Image(width: 12, height: 7)));
      expect(png!.mimeType, 'image/png');
      expect((png.width, png.height), (12, 7));
      final gif = await resize(img.encodeGif(img.Image(width: 5, height: 9)));
      expect(gif!.mimeType, 'image/gif');
      expect((gif.width, gif.height), (5, 9));
    });

    test('bytes that are not an image still fail', () async {
      expect(await resize(input), isNull);
      expect(await resize(Uint8List(0)), isNull);
      expect(calls, isEmpty);
    });

    test('a format a chat cannot show is refused', () async {
      final bmp = img.encodeBmp(img.Image(width: 4, height: 4));
      expect(await resize(bmp), isNull);
    });
  });
}
