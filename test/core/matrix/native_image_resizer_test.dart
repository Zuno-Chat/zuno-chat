import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/native_image_resizer.dart';

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
}
