import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/webrtc_backend.dart';

import '../../../helpers/native_method_calls.dart';

const _cameraOnly = {
  'audio': false,
  'video': {'facingMode': 'user'},
};

void main() {
  void captureAnswers(Object? Function() answer) {
    silenceMethodChannels(const ['FlutterWebRTC.Event']);
    recordMethodChannel(
      'FlutterWebRTC.Method',
      reply: (call) => call.method == 'getUserMedia' ? answer() : null,
    );
  }

  test('a camera capture that works hands back its stream', () async {
    captureAnswers(
      () => {'streamId': 'capture-1', 'audioTracks': [], 'videoTracks': []},
    );

    final stream = await const WebRtcBackend().getUserMedia(_cameraOnly);

    expect(stream.id, 'capture-1');
  });

  for (final (platform, refusal) in [
    (
      'Android',
      PlatformException(
        code: 'getUserMedia',
        message: 'getUserMedia(): DOMException, NotAllowedError',
      ),
    ),
    (
      'iOS',
      PlatformException(code: 'Error DOMException', message: 'NotAllowedError'),
    ),
  ]) {
    test('a camera refused on $platform is a camera refusal', () async {
      captureAnswers(() => throw refusal);

      await expectLater(
        const WebRtcBackend().getUserMedia(_cameraOnly),
        throwsA(isA<CameraRefused>()),
      );
    });
  }

  test('a camera that fails for another reason keeps its error', () async {
    captureAnswers(
      () => throw PlatformException(
        code: 'getUserMedia',
        message: 'getUserMedia(): camera is in use',
      ),
    );

    await expectLater(
      const WebRtcBackend().getUserMedia(_cameraOnly),
      throwsA(allOf(isNot(isA<CameraRefused>()), contains('camera is in use'))),
    );
  });

  test('a refusal of a capture that also asks for the microphone is not '
      'blamed on the camera', () async {
    captureAnswers(
      () => throw PlatformException(
        code: 'Error DOMException',
        message: 'NotAllowedError',
      ),
    );

    await expectLater(
      const WebRtcBackend().getUserMedia({..._cameraOnly, 'audio': true}),
      throwsA(isNot(isA<CameraRefused>())),
    );
  });
}
