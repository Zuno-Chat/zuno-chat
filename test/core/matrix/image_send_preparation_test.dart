import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:zuno/core/matrix/image_send_preparation.dart';
import 'package:zuno/core/matrix/media_processing_exception.dart';
import 'package:zuno/core/matrix/native_image_resizer.dart';

Uint8List _jpeg(int width, int height) =>
    img.encodeJpg(img.Image(width: width, height: height));

Uint8List _png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/image');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source = Uint8List.fromList(List.filled(64, 7));
  late List<MethodCall> calls;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answerWith(
    Map<String, Object?>? Function(int maxDimension, int quality) reply,
  ) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments as Map;
      return reply(args['maxDimension'] as int, args['quality'] as int);
    });
  }

  Map<String, Object?> jpegReply(int width, int height) => {
    'bytes': _jpeg(width, height),
    'width': width,
    'height': height,
    'mimeType': 'image/jpeg',
  };

  test('a large photo gets a 1080 main image and an 800 thumbnail', () async {
    answerWith(
      (max, quality) =>
          max == 1080 ? jpegReply(1080, 810) : jpegReply(800, 600),
    );
    final prepared = await prepareImageForSend(
      source,
      reduceMediaSize: false,
      resizer: NativeImageResizer.forTest(),
    );
    expect(calls.map((c) => (c.arguments as Map)['maxDimension']), [1080, 800]);
    expect(calls.map((c) => (c.arguments as Map)['quality']), everyElement(85));
    expect(prepared.file.name, 'photo.jpg');
    expect(prepared.file.mimeType, 'image/jpeg');
    expect(prepared.file.width, 1080);
    expect(prepared.file.height, 810);
    expect(prepared.file.blurhash, isNotNull);
    expect(prepared.thumbnail!.width, 800);
    expect(prepared.thumbnail!.height, 600);
    expect(prepared.thumbnail!.blurhash, prepared.file.blurhash);
  });

  test('reduce media size lowers both the dimension and the quality', () async {
    answerWith((max, quality) => jpegReply(720, 540));
    await prepareImageForSend(
      source,
      reduceMediaSize: true,
      resizer: NativeImageResizer.forTest(),
    );
    final first = calls.first.arguments as Map;
    expect(first['maxDimension'], 720);
    expect(first['quality'], 75);
  });

  test('a small photo gets no thumbnail', () async {
    answerWith((max, quality) => jpegReply(640, 480));
    final prepared = await prepareImageForSend(
      source,
      reduceMediaSize: false,
      resizer: NativeImageResizer.forTest(),
    );
    expect(calls, hasLength(1));
    expect(prepared.thumbnail, isNull);
  });

  test('a thumbnail no smaller than the main image is dropped', () async {
    answerWith(
      (max, quality) => max == 1080
          ? {
              'bytes': Uint8List.fromList(_jpeg(1080, 810).take(300).toList()),
              'width': 1080,
              'height': 810,
              'mimeType': 'image/jpeg',
            }
          : jpegReply(800, 600),
    );
    final prepared = await prepareImageForSend(
      source,
      reduceMediaSize: false,
      resizer: NativeImageResizer.forTest(),
    );
    expect(prepared.thumbnail, isNull);
  });

  test('a PNG source stays PNG and is named accordingly', () async {
    answerWith(
      (max, quality) => {
        'bytes': _png(900, 900),
        'width': 900,
        'height': 900,
        'mimeType': 'image/png',
      },
    );
    final prepared = await prepareImageForSend(
      source,
      reduceMediaSize: false,
      resizer: NativeImageResizer.forTest(),
    );
    expect(prepared.file.name, 'photo.png');
    expect(prepared.file.mimeType, 'image/png');
  });

  test('progress runs 0, then half after the main image, then done', () async {
    answerWith(
      (max, quality) =>
          max == 1080 ? jpegReply(1080, 810) : jpegReply(800, 600),
    );
    final progress = <double>[];
    await prepareImageForSend(
      source,
      reduceMediaSize: false,
      resizer: NativeImageResizer.forTest(),
      onProgress: progress.add,
    );
    expect(progress, [0, 0.5, 1]);
  });

  test('an undecodable photo is refused', () async {
    answerWith((max, quality) => null);
    expect(
      () => prepareImageForSend(
        source,
        reduceMediaSize: false,
        resizer: NativeImageResizer.forTest(),
      ),
      throwsA(
        isA<MediaProcessingException>().having(
          (e) => e.message,
          'message',
          'Cannot send this photo',
        ),
      ),
    );
  });

  test('a failed thumbnail does not block the send', () async {
    answerWith((max, quality) => max == 1080 ? jpegReply(1080, 810) : null);
    final prepared = await prepareImageForSend(
      source,
      reduceMediaSize: false,
      resizer: NativeImageResizer.forTest(),
    );
    expect(prepared.thumbnail, isNull);
    expect(prepared.file.width, 1080);
  });

  test('blurhashOf encodes a decodable image and rejects garbage', () {
    expect(blurhashOf(_jpeg(64, 48)), isNotNull);
    expect(blurhashOf(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
