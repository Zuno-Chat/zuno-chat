import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/media/video_codec.dart';

void main() {
  test('lists the sent codec first, keeping every other payload in its '
      'order', () {
    expect(
      withSentVideoCodecFirst([
        'm=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97',
        'a=rtpmap:102 H264/90000',
        'a=rtpmap:103 rtx/90000',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 rtx/90000',
      ]).first,
      'm=video 9 UDP/TLS/RTP/SAVPF 96 102 103 97',
    );
  });

  test('matches the codec name in any case', () {
    expect(
      withSentVideoCodecFirst([
        'm=video 9 UDP/TLS/RTP/SAVPF 102 96',
        'a=rtpmap:102 H264/90000',
        'a=rtpmap:96 vp8/90000',
      ]).first,
      'm=video 9 UDP/TLS/RTP/SAVPF 96 102',
    );
  });

  test('a section without the sent codec keeps its order', () {
    final section = [
      'm=video 9 UDP/TLS/RTP/SAVPF 102 103',
      'a=rtpmap:102 H264/90000',
      'a=rtpmap:103 rtx/90000',
    ];

    expect(withSentVideoCodecFirst(section), section);
  });
}
