import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/media_processing_exception.dart';
import 'package:zuno/core/matrix/video_compression.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const compressor = MethodChannel('light_compressor');
  const progress = EventChannel('compression/stream');

  late List<Map<Object?, Object?>> requests;
  late Future<Object?> Function() answer;

  setUp(() {
    requests = [];
    answer = () async => jsonEncode({'onSuccess': '/cache/out.mp4'});
    messenger.setMockMethodCallHandler(compressor, (call) async {
      requests.add(call.arguments as Map<Object?, Object?>);
      return answer();
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(compressor, null);
      messenger.setMockStreamHandler(progress, null);
    });
  });

  Future<String> reencode({
    int? width = 1280,
    int? height = 720,
    void Function(double fraction)? onProgress,
  }) => reencodeVideo(
    '/videos/in.mp4',
    width: width,
    height: height,
    bitrateMbps: 3,
    onProgress: onProgress,
  );

  test('hands back the re-encoded file', () async {
    expect(await reencode(), '/cache/out.mp4');

    final request = requests.single;
    expect(request['path'], '/videos/in.mp4');
    expect(request['videoBitrateInMbps'], 3);
    expect(request['videoQuality'], 'medium');
    expect(request['isSharedStorage'], isFalse);
    expect(request['saveInGallery'], isFalse);
    expect(request['isMinBitrateCheckEnabled'], isFalse);
  });

  test('asks for landscape video in its own orientation', () async {
    await reencode(width: 1280, height: 720);

    expect(requests.single['videoWidth'], 1280);
    expect(requests.single['videoHeight'], 720);
  });

  test('asks for portrait video in the encoder\'s raw orientation', () async {
    await reencode(width: 720, height: 1280);

    expect(requests.single['videoWidth'], 1280);
    expect(requests.single['videoHeight'], 720);
  });

  test('leaves the size to the encoder when it is unknown', () async {
    await reencode(width: null, height: null);

    expect(requests.single['videoWidth'], isNull);
    expect(requests.single['videoHeight'], isNull);
  });

  test('reports progress as a fraction, capped at done', () async {
    messenger.setMockStreamHandler(
      progress,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink.success(50.0);
          sink.success(140.0);
        },
      ),
    );
    answer = () async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return jsonEncode({'onSuccess': '/cache/out.mp4'});
    };
    final fractions = <double>[];

    await reencode(onProgress: fractions.add);

    expect(fractions, [0.5, 1.0]);
  });

  for (final (label, response) in [
    ('the encoder fails', {'onFailure': 'codec error'}),
    ('the encoding is cancelled', {'onCancelled': true}),
    ('the encoder answers nothing useful', <String, Object?>{}),
  ]) {
    test('says the video cannot be sent when $label', () async {
      answer = () async => jsonEncode(response);

      await expectLater(reencode(), throwsA(same(videoSendFailure)));
    });
  }

  test('says the video cannot be sent when the encoder crashes', () async {
    answer = () async => throw PlatformException(code: 'crash');

    await expectLater(reencode(), throwsA(isA<MediaProcessingException>()));
  });
}
