import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/call_quality_policy.dart';
import 'package:zuno/core/calls/cloudflare/send_params.dart';

String sdp(List<String> lines) => '${lines.join('\r\n')}\r\n';

void main() {
  const session = ['v=0', 'o=- 1 2 IN IP4 127.0.0.1', 's=-', 't=0 0'];

  test('turns on in-band FEC and keeps silence suppression off, so a muted '
      'microphone still sends, keeping what else the Opus line says', () {
    final result = withSendParams(
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
    final result = withSendParams(
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
    final result = withSendParams(
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

  test('leaves other audio codecs alone', () {
    final original = sdp([
      ...session,
      'm=audio 9 UDP/TLS/RTP/SAVPF 63 111',
      'a=rtpmap:63 red/48000/2',
      'a=fmtp:63 111/111',
      'a=rtpmap:111 opus/48000/2',
      'a=fmtp:111 useinbandfec=1;usedtx=0',
    ]);

    expect(withSendParams(original), original);
  });

  test('starts the bandwidth estimate on every video codec, keeping what '
      'else its line says', () {
    final result = withSendParams(
      sdp([
        ...session,
        'm=video 9 UDP/TLS/RTP/SAVPF 96 102',
        'a=recvonly',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:102 H264/90000',
        'a=fmtp:102 packetization-mode=1;profile-level-id=42e01f',
      ]),
    );

    expect(
      result,
      contains(
        'a=rtpmap:96 VP8/90000\r\n'
        'a=fmtp:96 x-google-start-bitrate=$startBitrateKbps\r\n',
      ),
    );
    expect(
      result,
      contains(
        'a=fmtp:102 packetization-mode=1;profile-level-id=42e01f;'
        'x-google-start-bitrate=$startBitrateKbps\r\n',
      ),
    );
  });

  test('replaces a start the answer already sets', () {
    final result = withSendParams(
      sdp([
        ...session,
        'm=video 9 UDP/TLS/RTP/SAVPF 96',
        'a=rtpmap:96 VP8/90000',
        'a=fmtp:96 x-google-start-bitrate=100',
      ]),
    );

    expect(
      result,
      contains('a=fmtp:96 x-google-start-bitrate=$startBitrateKbps\r\n'),
    );
    expect(result, isNot(contains('=100')));
  });

  test('leaves video we only receive alone, so pulling someone\'s tracks '
      'never restarts the bandwidth estimate', () {
    final original = sdp([
      ...session,
      'm=video 9 UDP/TLS/RTP/SAVPF 96',
      'a=sendonly',
      'a=rtpmap:96 VP8/90000',
      'm=video 9 UDP/TLS/RTP/SAVPF 96',
      'a=inactive',
      'a=rtpmap:96 VP8/90000',
    ]);

    expect(withSendParams(original), original);
  });

  test('leaves retransmission, redundancy and error correction alone', () {
    final original = sdp([
      ...session,
      'm=video 9 UDP/TLS/RTP/SAVPF 97 98 99',
      'a=rtpmap:97 rtx/90000',
      'a=fmtp:97 apt=96',
      'a=rtpmap:98 red/90000',
      'a=rtpmap:99 ulpfec/90000',
    ]);

    expect(withSendParams(original), original);
  });

  test('passes anything that is not an SDP through untouched', () {
    expect(withSendParams('sfu answer 1'), 'sfu answer 1');
  });
}
