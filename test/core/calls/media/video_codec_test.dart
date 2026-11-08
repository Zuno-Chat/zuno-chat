import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/media/call_quality_policy.dart';
import 'package:zuno/core/calls/media/video_codec.dart';

void main() {
  String videoLine(List<String> section) => withSentVideoParams(
    [
      'v=0',
      'o=- 1 2 IN IP4 127.0.0.1',
      's=-',
      't=0 0',
      ...section,
      '',
    ].join('\r\n'),
  ).split('\r\n').firstWhere((line) => line.startsWith('m=video'));

  test('lists the sent codec first, keeping every other payload in its '
      'order', () {
    expect(
      videoLine([
        'm=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97',
        'a=rtpmap:102 H264/90000',
        'a=rtpmap:103 rtx/90000',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 rtx/90000',
      ]),
      'm=video 9 UDP/TLS/RTP/SAVPF 96 102 103 97',
    );
  });

  test('matches the codec name in any case', () {
    expect(
      videoLine([
        'm=video 9 UDP/TLS/RTP/SAVPF 102 96',
        'a=rtpmap:102 H264/90000',
        'a=rtpmap:96 vp8/90000',
      ]),
      'm=video 9 UDP/TLS/RTP/SAVPF 96 102',
    );
  });

  test('a section without the sent codec keeps its order', () {
    expect(
      videoLine([
        'm=video 9 UDP/TLS/RTP/SAVPF 102 103',
        'a=rtpmap:102 H264/90000',
        'a=rtpmap:103 rtx/90000',
      ]),
      'm=video 9 UDP/TLS/RTP/SAVPF 102 103',
    );
  });

  group('sent video params', () {
    String sdp(List<String> lines) => '${lines.join('\r\n')}\r\n';
    const session = ['v=0', 'o=- 1 2 IN IP4 127.0.0.1', 's=-', 't=0 0'];

    test('a sent video section lists VP8 first and starts every video codec '
        'at the start bitrate, leaving its helpers alone', () {
      final result = withSentVideoParams(
        sdp([
          ...session,
          'm=video 9 UDP/TLS/RTP/SAVPF 102 96 97',
          'a=recvonly',
          'a=rtpmap:102 H264/90000',
          'a=fmtp:102 profile-level-id=42e01f',
          'a=rtpmap:96 VP8/90000',
          'a=rtpmap:97 rtx/90000',
          'a=fmtp:97 apt=96',
        ]),
      );

      expect(
        result,
        sdp([
          ...session,
          'm=video 9 UDP/TLS/RTP/SAVPF 96 102 97',
          'a=recvonly',
          'a=rtpmap:102 H264/90000',
          'a=fmtp:102 profile-level-id=42e01f;'
              'x-google-start-bitrate=$startBitrateKbps',
          'a=rtpmap:96 VP8/90000',
          'a=fmtp:96 x-google-start-bitrate=$startBitrateKbps',
          'a=rtpmap:97 rtx/90000',
          'a=fmtp:97 apt=96',
        ]),
      );
    });

    test('a video section we do not send and every audio section stay as '
        'they are', () {
      final original = sdp([
        ...session,
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 minptime=10',
        'm=video 9 UDP/TLS/RTP/SAVPF 102 96',
        'a=sendonly',
        'a=rtpmap:102 H264/90000',
        'a=rtpmap:96 VP8/90000',
      ]);

      expect(withSentVideoParams(original), original);
    });

    test('a description with no media sections is unchanged', () {
      expect(withSentVideoParams('lk answer 1'), 'lk answer 1');
    });
  });
}
