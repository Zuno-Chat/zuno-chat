import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/cloudflare/placeholder_video.dart';

import '../../../helpers/native_method_calls.dart';

void main() {
  late RecordedMethodCalls webrtc;

  void answerWebRtc() {
    silenceMethodChannels(const ['FlutterWebRTC.Event']);
    webrtc = recordMethodChannel(
      'FlutterWebRTC.Method',
      reply: (call) => switch (call.method) {
        'createLocalMediaStream' => {'streamId': 'placeholder-stream'},
        _ => null,
      },
    );
  }

  test(
    'a native track attaches to a fresh stream and is handed back',
    () async {
      answerWebRtc();
      final zuno = recordMethodChannel(
        'zuno/calls',
        reply: (call) =>
            call.method == 'attachPlaceholderVideo' ? 'black-1' : null,
      );

      final placeholder = await const PlaceholderVideoSource().create();

      expect(placeholder!.stream.id, 'placeholder-stream');
      expect(placeholder.track.id, 'black-1');
      expect(placeholder.track.kind, 'video');
      expect(zuno.valuesOf('attachPlaceholderVideo', 'streamId'), [
        'placeholder-stream',
      ]);
    },
  );

  test('a platform without the plugin has no placeholder', () async {
    answerWebRtc();
    recordMethodChannel(
      'zuno/calls',
      reply: (call) => throw MissingPluginException(),
    );

    expect(await const PlaceholderVideoSource().create(), isNull);
    expect(webrtc.named('streamDispose'), hasLength(1));
  });

  test('a native failure disposes the stream and is rethrown', () async {
    answerWebRtc();
    recordMethodChannel(
      'zuno/calls',
      reply: (call) => throw PlatformException(code: 'attach'),
    );

    await expectLater(
      const PlaceholderVideoSource().create(),
      throwsA(isA<PlatformException>()),
    );
    expect(webrtc.named('streamDispose'), hasLength(1));
  });

  test(
    'release disposes the stream and tells native to drop the track',
    () async {
      answerWebRtc();
      final zuno = recordMethodChannel(
        'zuno/calls',
        reply: (call) =>
            call.method == 'attachPlaceholderVideo' ? 'black-1' : null,
      );
      const source = PlaceholderVideoSource();
      final placeholder = (await source.create())!;

      await source.release(placeholder);

      expect(webrtc.named('streamDispose'), hasLength(1));
      expect(zuno.valuesOf('releasePlaceholderVideo', 'trackId'), ['black-1']);
    },
  );
}
