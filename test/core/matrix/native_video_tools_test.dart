import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/native_video_tools.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tools = NativeVideoTools.forTest();
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) reply) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('probe sends the path and parses every field', () async {
    answer(
      (_) => {
        'width': 1280,
        'height': 720,
        'bitrate': 2000000,
        'durationMs': 5000,
        'videoCodec': 'video/avc',
        'audioCodec': 'audio/mp4a-latm',
        'rotated': true,
      },
    );
    final probe = await tools.probe('/tmp/a.mp4');
    expect(calls.single.method, 'probe');
    expect(calls.single.arguments, {'path': '/tmp/a.mp4'});
    expect(probe!.width, 1280);
    expect(probe.height, 720);
    expect(probe.bitrate, 2000000);
    expect(probe.durationMs, 5000);
    expect(probe.videoCodec, 'video/avc');
    expect(probe.audioCodec, 'audio/mp4a-latm');
    expect(probe.rotated, isTrue);
  });

  test('probe tolerates missing optional fields', () async {
    answer((_) => {'width': 640, 'height': 480});
    final probe = await tools.probe('/tmp/a.mp4');
    expect(probe!.bitrate, isNull);
    expect(probe.durationMs, isNull);
    expect(probe.videoCodec, isNull);
    expect(probe.audioCodec, isNull);
    expect(probe.rotated, isNull);
  });

  test('probe needs real dimensions', () async {
    answer((_) => {'width': 0, 'height': 480});
    expect(await tools.probe('/tmp/a.mp4'), isNull);
    answer((_) => null);
    expect(await tools.probe('/tmp/a.mp4'), isNull);
  });

  test('remux passes both paths and reports the native outcome', () async {
    answer((_) => true);
    expect(await tools.remux('/in.mp4', '/out.mp4'), isTrue);
    expect(calls.single.arguments, {'input': '/in.mp4', 'output': '/out.mp4'});
    answer((_) => null);
    expect(await tools.remux('/in.mp4', '/out.mp4'), isFalse);
  });

  test('thumbnail passes the limits and parses the image', () async {
    final bytes = Uint8List.fromList([1, 2]);
    answer(
      (_) => {
        'bytes': bytes,
        'width': 800,
        'height': 450,
        'mimeType': 'image/jpeg',
      },
    );
    final thumb = await tools.thumbnail(
      '/tmp/a.mp4',
      maxDimension: 800,
      quality: 85,
    );
    expect(calls.single.arguments, {
      'path': '/tmp/a.mp4',
      'maxDimension': 800,
      'quality': 85,
    });
    expect(thumb!.bytes, bytes);
    expect(thumb.width, 800);
    expect(thumb.height, 450);
  });

  test('native errors read as failures instead of throwing', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    expect(await tools.probe('/tmp/a.mp4'), isNull);
    expect(await tools.remux('/in.mp4', '/out.mp4'), isFalse);
    expect(
      await tools.thumbnail('/tmp/a.mp4', maxDimension: 800, quality: 85),
      isNull,
    );
  });

  test('with android capabilities every call goes native', () async {
    answer((_) => null);
    final android = NativeVideoTools.forTest(
      capabilities: capabilitiesFor(AppPlatform.android),
    );
    await android.probe('/tmp/a.mp4');
    await android.remux('/in.mp4', '/out.mp4');
    await android.thumbnail('/tmp/a.mp4', maxDimension: 800, quality: 85);
    expect(calls.map((c) => c.method), ['probe', 'remux', 'thumbnail']);
  });

  test(
    'without native video tools nothing is probed, remuxed or thumbnailed',
    () async {
      answer((_) => null);
      final ios = NativeVideoTools.forTest(
        capabilities: capabilitiesLike(
          iosCapabilities,
          nativeVideoTools: false,
        ),
      );
      expect(await ios.probe('/tmp/a.mp4'), isNull);
      expect(await ios.remux('/in.mp4', '/out.mp4'), isFalse);
      expect(
        await ios.thumbnail('/tmp/a.mp4', maxDimension: 800, quality: 85),
        isNull,
      );
      expect(calls, isEmpty);
    },
  );
}
