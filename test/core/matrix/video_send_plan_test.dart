import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/video_send_plan.dart';

void main() {
  VideoSendPlan plan({
    int? width = 720,
    int? height = 404,
    int? bitrate = 2000000,
    String? videoCodec = h264Codec,
    String? audioCodec = aacCodec,
    bool reduceMediaSize = false,
  }) => planVideoSend(
    width: width,
    height: height,
    bitrate: bitrate,
    videoCodec: videoCodec,
    audioCodec: audioCodec,
    reduceMediaSize: reduceMediaSize,
  );

  Matcher reencode(int? width, int? height, int mbps) => isA<ReencodeVideo>()
      .having((p) => p.targetWidth, 'targetWidth', width)
      .having((p) => p.targetHeight, 'targetHeight', height)
      .having((p) => p.bitrateMbps, 'bitrateMbps', mbps);

  group('remux', () {
    test('a clip within the 720 long-edge cap at its target bitrate', () {
      expect(plan(), isA<RemuxVideo>());
    });

    test('portrait clips within the cap remux too', () {
      expect(plan(width: 404, height: 720), isA<RemuxVideo>());
    });

    test('a clip a little over the target bitrate is left alone', () {
      expect(plan(bitrate: 2400000), isA<RemuxVideo>());
    });

    test('no audio track is fine', () {
      expect(plan(audioCodec: null), isA<RemuxVideo>());
    });

    test('a 480 clip under its own target is remuxed', () {
      expect(
        plan(width: 480, height: 270, bitrate: 1000000),
        isA<RemuxVideo>(),
      );
    });
  });

  group('re-encode', () {
    test('anything over the 720 long-edge cap is scaled down at 2 Mbps', () {
      expect(
        plan(width: 1920, height: 1080, bitrate: 8000000),
        reencode(720, 404, 2),
      );
      expect(
        plan(width: 1280, height: 720, bitrate: 2000000),
        reencode(720, 404, 2),
      );
    });

    test('a clip well over the target bitrate is re-encoded in place', () {
      expect(plan(bitrate: 2600000), reencode(720, 404, 2));
    });

    test('a weak source never gets a bitrate above its own', () {
      expect(
        plan(width: 1920, height: 1080, bitrate: 1500000),
        reencode(720, 404, 1),
      );
    });

    test('bitrate never drops below 1 Mbps', () {
      expect(
        plan(width: 1920, height: 1080, bitrate: 400000),
        reencode(720, 404, 1),
      );
    });

    test('a small clip is capped at 1 Mbps', () {
      expect(
        plan(width: 480, height: 270, bitrate: 3000000),
        reencode(480, 270, 1),
      );
    });

    test('non-H.264 video is re-encoded even when small', () {
      expect(plan(videoCodec: 'video/hevc'), reencode(720, 404, 2));
    });

    test('non-AAC audio forces a re-encode', () {
      expect(plan(audioCodec: 'audio/opus'), reencode(720, 404, 2));
    });

    test('an unknown bitrate is re-encoded at the target', () {
      expect(plan(bitrate: null), reencode(720, 404, 2));
    });

    test('unknown dimensions re-encode with no size and the cap bitrate', () {
      expect(plan(width: null, height: null), reencode(null, null, 2));
      expect(
        plan(width: null, height: null, reduceMediaSize: true),
        reencode(null, null, 1),
      );
    });

    test('reduce media size caps at 480 and 1 Mbps', () {
      expect(plan(reduceMediaSize: true), reencode(480, 268, 1));
    });
  });
}
