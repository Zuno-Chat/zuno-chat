import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:zuno/core/matrix/media_processing_exception.dart';
import 'package:zuno/core/matrix/native_video_tools.dart';
import 'package:zuno/core/matrix/video_send_preparation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tools = NativeVideoTools.forTest();
  final remuxBytes = [1, 2, 3, 4];
  final reencodedBytes = [9, 9];
  late Directory workDir;
  late List<String> nativeCalls;
  late List<({int? width, int? height, int bitrateMbps})> reencodes;
  late bool reencoderFails;

  final probe720 = {
    'width': 720,
    'height': 404,
    'bitrate': 2000000,
    'durationMs': 5000,
    'videoCodec': 'video/avc',
    'audioCodec': 'audio/mp4a-latm',
  };
  final probe1080 = {
    ...probe720,
    'width': 1920,
    'height': 1080,
    'bitrate': 8000000,
  };

  void installNative({
    required Map<String, Object?>? probe,
    bool thumbnail = true,
    bool remuxSucceeds = true,
  }) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      final args = call.arguments as Map;
      switch (call.method) {
        case 'probe':
          return probe;
        case 'thumbnail':
          if (!thumbnail) return null;
          return {
            'bytes': img.encodeJpg(img.Image(width: 80, height: 45)),
            'width': 800,
            'height': 450,
            'mimeType': 'image/jpeg',
          };
        case 'remux':
          if (!remuxSucceeds) return false;
          File(args['output'] as String).writeAsBytesSync(remuxBytes);
          return true;
      }
      return null;
    });
  }

  Future<String> fakeReencoder(
    String path, {
    required int? width,
    required int? height,
    required int bitrateMbps,
    void Function(double fraction)? onProgress,
  }) async {
    nativeCalls.add('reencode');
    reencodes.add((width: width, height: height, bitrateMbps: bitrateMbps));
    if (reencoderFails) throw const MediaProcessingException('nope');
    onProgress?.call(0.5);
    final out = File(p.join(workDir.path, 'reencoded.mp4'));
    out.writeAsBytesSync(reencodedBytes);
    return out.path;
  }

  Future<PreparedVideo> prepare({
    bool reduceMediaSize = false,
    void Function(double)? onProgress,
    void Function(Object)? onThumbnail,
    int? fallbackWidth,
    int? fallbackHeight,
    int? fallbackDurationMs,
  }) => prepareVideoForSend(
    '/source.mp4',
    reduceMediaSize: reduceMediaSize,
    tools: tools,
    reencoder: fakeReencoder,
    workDir: workDir,
    onProgress: onProgress,
    onThumbnail: onThumbnail,
    fallbackWidth: fallbackWidth,
    fallbackHeight: fallbackHeight,
    fallbackDurationMs: fallbackDurationMs,
  );

  Future<void> settleDeletes() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('zuno_video_send');
    nativeCalls = [];
    reencodes = [];
    reencoderFails = false;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    workDir.deleteSync(recursive: true);
  });

  test('a clip that already fits is remuxed, not re-encoded', () async {
    installNative(probe: probe720);
    final progress = <double>[];
    var previews = 0;
    final prepared = await prepare(
      onProgress: progress.add,
      onThumbnail: (_) => previews++,
    );
    expect(nativeCalls, ['probe', 'thumbnail', 'remux']);
    expect(previews, 1);
    expect(reencodes, isEmpty);
    expect(prepared.file.bytes, remuxBytes);
    expect(prepared.file.name, 'video.mp4');
    expect(prepared.file.width, 720);
    expect(prepared.file.height, 404);
    expect(prepared.file.duration, 5000);
    expect(prepared.thumbnail!.name, 'thumbnail.jpg');
    expect(prepared.thumbnail!.width, 800);
    expect(prepared.thumbnail!.height, 450);
    expect(prepared.thumbnail!.blurhash, isNotNull);
    expect(progress, [0, 1]);
    await settleDeletes();
    expect(workDir.listSync(), isEmpty);
  });

  test(
    'a larger clip is re-encoded to the plan and progress flows through',
    () async {
      installNative(probe: probe1080);
      final progress = <double>[];
      final prepared = await prepare(onProgress: progress.add);
      expect(nativeCalls, ['probe', 'thumbnail', 'reencode']);
      expect(reencodes.single, (width: 720, height: 404, bitrateMbps: 2));
      expect(prepared.file.bytes, reencodedBytes);
      expect(prepared.file.width, 720);
      expect(prepared.file.height, 404);
      expect(progress, [0, 0.5, 1]);
      await settleDeletes();
      expect(workDir.listSync(), isEmpty);
    },
  );

  test('a failed remux falls back to re-encoding', () async {
    installNative(probe: probe720, remuxSucceeds: false);
    final prepared = await prepare();
    expect(nativeCalls, ['probe', 'thumbnail', 'remux', 'reencode']);
    expect(reencodes.single, (width: 720, height: 404, bitrateMbps: 2));
    expect(prepared.file.bytes, reencodedBytes);
  });

  test(
    'a failed re-encode refuses the send and leaves nothing behind',
    () async {
      installNative(probe: probe1080);
      reencoderFails = true;
      await expectLater(prepare(), throwsA(isA<MediaProcessingException>()));
      await settleDeletes();
      expect(workDir.listSync(), isEmpty);
    },
  );

  test('without a probe the composer values drive the plan', () async {
    installNative(probe: null);
    final prepared = await prepare(
      fallbackWidth: 640,
      fallbackHeight: 360,
      fallbackDurationMs: 1234,
    );
    expect(reencodes.single, (width: 640, height: 360, bitrateMbps: 1));
    expect(prepared.file.width, 640);
    expect(prepared.file.height, 360);
    expect(prepared.file.duration, 1234);
  });

  test('a missing thumbnail does not block the send', () async {
    installNative(probe: probe720, thumbnail: false);
    var previews = 0;
    final prepared = await prepare(onThumbnail: (_) => previews++);
    expect(prepared.thumbnail, isNull);
    expect(previews, 0);
    expect(prepared.file.bytes, remuxBytes);
  });
}
