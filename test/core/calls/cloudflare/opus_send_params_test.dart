import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/opus_send_params.dart';

String sdp(List<String> lines) => '${lines.join('\r\n')}\r\n';

void main() {
  const session = ['v=0', 'o=- 1 2 IN IP4 127.0.0.1', 's=-', 't=0 0'];

  test('turns on in-band FEC and keeps silence suppression off, so a muted '
      'microphone still sends, keeping what else the Opus line says', () {
    final result = withOpusSendParams(
      sdp([
        ...session,
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=mid:0',
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 minptime=10;useinbandfec=0;usedtx=1',
      ]),
    );

    expect(
      result,
      contains('a=fmtp:111 minptime=10;useinbandfec=1;usedtx=0\r\n'),
    );
    expect(result, isNot(contains('usedtx=1')));
  });

  test('adds the Opus line when the SDP has none', () {
    final result = withOpusSendParams(
      sdp([
        ...session,
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=rtpmap:111 opus/48000/2',
        'a=rtcp-fb:111 transport-cc',
      ]),
    );

    expect(
      result,
      contains(
        'a=rtpmap:111 opus/48000/2\r\n'
        'a=fmtp:111 useinbandfec=1;usedtx=0\r\n'
        'a=rtcp-fb:111 transport-cc\r\n',
      ),
    );
  });

  test('changes every audio section, under its own payload type', () {
    final result = withOpusSendParams(
      sdp([
        ...session,
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 minptime=10',
        'm=audio 9 UDP/TLS/RTP/SAVPF 109',
        'a=rtpmap:109 OPUS/48000/2',
        'a=fmtp:109 minptime=10',
      ]),
    );

    expect(result, contains('a=fmtp:111 minptime=10;useinbandfec=1;usedtx=0'));
    expect(result, contains('a=fmtp:109 minptime=10;useinbandfec=1;usedtx=0'));
  });

  test('leaves other codecs and video alone', () {
    final original = sdp([
      ...session,
      'm=audio 9 UDP/TLS/RTP/SAVPF 63 111',
      'a=rtpmap:63 red/48000/2',
      'a=fmtp:63 111/111',
      'a=rtpmap:111 opus/48000/2',
      'a=fmtp:111 useinbandfec=1;usedtx=0',
      'm=video 9 UDP/TLS/RTP/SAVPF 96',
      'a=rtpmap:96 VP8/90000',
      'a=fmtp:96 x-google-start-bitrate=800',
    ]);

    expect(withOpusSendParams(original), original);
  });

  test('passes anything that is not an SDP through untouched', () {
    expect(withOpusSendParams('sfu answer 1'), 'sfu answer 1');
  });
}
