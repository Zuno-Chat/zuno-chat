import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/cloudflare/video_codec_preference.dart';

void main() {
  RTCRtpCodecCapability codec(String mime, {String? fmtp}) =>
      RTCRtpCodecCapability(
        mimeType: mime,
        clockRate: 90000,
        sdpFmtpLine: fmtp,
      );

  test('moves VP8 first, then H264, keeping everything else in order', () {
    final ordered = orderVideoCodecs([
      codec('video/H264', fmtp: 'profile-level-id=42e01f'),
      codec('video/rtx'),
      codec('video/VP9'),
      codec('video/VP8'),
      codec('video/red'),
      codec('video/H264', fmtp: 'profile-level-id=640c1f'),
    ]);
    expect(ordered.map((c) => c.mimeType).toList(), [
      'video/VP8',
      'video/H264',
      'video/H264',
      'video/rtx',
      'video/VP9',
      'video/red',
    ]);
    expect(ordered[1].sdpFmtpLine, 'profile-level-id=42e01f');
  });

  test('matches mime types case-insensitively', () {
    final ordered = orderVideoCodecs([codec('video/h264'), codec('video/vp8')]);
    expect(ordered.first.mimeType, 'video/vp8');
  });

  test('a list without any preferred codec is returned unchanged', () {
    final input = [codec('video/AV1'), codec('video/VP9')];
    expect(orderVideoCodecs(input).map((c) => c.mimeType), [
      'video/AV1',
      'video/VP9',
    ]);
  });
}
