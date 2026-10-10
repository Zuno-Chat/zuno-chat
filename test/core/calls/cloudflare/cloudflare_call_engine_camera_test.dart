import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_webrtc.dart';
import '../../../helpers/platform_capabilities.dart';
import 'cloudflare_engine_harness.dart';

void main() {
  void inCall(
    void Function(EngineHarness call) body, {
    CallKind kind = CallKind.video,
    PlatformCapabilities? capabilities,
  }) => runEngineCall(
    body,
    kind: kind,
    capabilities: capabilities ?? androidCapabilities,
  );

  Matcher placeholderOf(EngineHarness call) =>
      same(call.backend.placeholders.last.track);

  group('turning the camera off', () {
    test('sends the black placeholder and stops the camera', () {
      inCall((call) {
        call.joinEncrypted();
        final cameraStream = call.local.videoStream! as FakeMediaStream;

        call.wait(call.engine.setCameraEnabled(false));

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(cameraStream.disposed, isTrue);
        expect(call.local.videoEnabled, isFalse);
        expect(call.local.videoStream, isNull);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
        expect(call.sfu.pushes, hasLength(1));
      });
    });

    test('and on again restarts the camera it was on, sends it encrypted '
        'and releases the placeholder', () {
      inCall((call) {
        call.joinEncrypted();
        call.wait(call.engine.switchCamera());
        call.wait(call.engine.setCameraEnabled(false));

        call.wait(call.engine.setCameraEnabled(true));

        expect(call.backend.captureConstraints.last, {
          'audio': false,
          'video': {
            'facingMode': 'environment',
            'width': 854,
            'height': 480,
            'frameRate': 30,
          },
        });
        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.camera.enabled, isTrue);
        expect(call.backend.cryptors.liveLabels, contains('local-video'));
        expect(call.backend.releasedPlaceholders, call.backend.placeholders);
        expect(call.local.videoEnabled, isTrue);
        expect(call.local.frontCamera, isFalse);
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
        expect(call.sfu.pushes, hasLength(1));
      });
    });

    test('without a placeholder only disables the camera, so its video '
        'stays published', () {
      inCall((call) {
        call.backend.placeholderAvailable = false;
        call.joinEncrypted();
        final cameraStream = call.local.videoStream! as FakeMediaStream;

        call.wait(call.engine.setCameraEnabled(false));

        expect(call.camera.enabled, isFalse);
        expect(call.videoSlot.sender.track, same(call.camera));
        expect(cameraStream.disposed, isFalse);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);

        call.wait(call.engine.setCameraEnabled(true));

        expect(call.camera.enabled, isTrue);
        expect(call.backend.captures, hasLength(1));
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      });
    });

    test('turning it off while it is still restarting ends with the camera '
        'stopped', () {
      inCall((call) {
        call.joinEncrypted();
        call.wait(call.engine.setCameraEnabled(false));
        final gate = Completer<void>();
        call.backend.captureGate = gate;

        final on = call.engine.setCameraEnabled(true);
        call.flush();
        final off = call.engine.setCameraEnabled(false);
        gate.complete();
        call.wait(Future.wait([on, off]));

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(call.backend.captures, hasLength(2));
        expect(call.backend.captures.last.disposed, isTrue);
        expect(call.local.videoEnabled, isFalse);
        expect(call.local.videoStream, isNull);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
      });
    });

    test('a camera that cannot restart stays off, with the placeholder still '
        'in place', () {
      inCall((call) {
        call.joinEncrypted();
        call.wait(call.engine.setCameraEnabled(false));
        call.backend.captureError = StateError('camera in use');

        expect(
          () => call.wait(call.engine.setCameraEnabled(true)),
          throwsA(isA<StateError>()),
        );

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(call.backend.releasedPlaceholders, isEmpty);
        expect(call.local.videoEnabled, isFalse);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
      });
    });

    test('in a voice call, turning the camera on switches the call to '
        'video', () {
      inCall((call) {
        call.joinEncrypted();

        call.wait(call.engine.setCameraEnabled(true));

        expect(call.engine.kind, CallKind.video);
        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.backend.releasedPlaceholders, call.backend.placeholders);
      }, kind: CallKind.voice);
    });

    test('leaving after a restart releases the restarted camera', () {
      inCall((call) {
        call.joinEncrypted();
        call.wait(call.engine.setCameraEnabled(false));
        call.wait(call.engine.setCameraEnabled(true));
        final restarted = call.backend.captures.last;
        final cameraStream = call.local.videoStream! as FakeMediaStream;

        call.leave();

        expect(restarted.disposed, isTrue);
        expect(cameraStream.disposed, isTrue);
      });
    });
  });

  group('in the background', () {
    test('where the camera stops in the background, the placeholder covers '
        'it and the camera comes back with the app', () {
      inCall((call) {
        call.joinEncrypted();
        final camera = call.camera;
        final cameraStream = call.local.videoStream! as FakeMediaStream;
        final changes = call.localStateChanges;

        call.wait(call.engine.setAppInBackground(true));

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(cameraStream.disposed, isFalse);
        expect(call.local.videoEnabled, isTrue);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
        expect(call.localStateChanges, greaterThan(changes));

        call.wait(call.engine.setAppInBackground(false));

        expect(call.videoSlot.sender.track, same(camera));
        expect(call.backend.captures, hasLength(1));
        expect(call.backend.releasedPlaceholders, call.backend.placeholders);
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, capabilities: iosCapabilities);
    });

    test('where the camera would keep running in the background, the '
        'placeholder covers it, the camera stops and comes back with the '
        'app', () {
      inCall((call) {
        call.joinEncrypted();
        final cameraStream = call.local.videoStream! as FakeMediaStream;
        final changes = call.localStateChanges;

        call.wait(call.engine.setAppInBackground(true));

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(cameraStream.disposed, isTrue);
        expect(call.local.videoEnabled, isTrue);
        expect(call.local.videoStream, isNull);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
        expect(call.localStateChanges, greaterThan(changes));

        call.wait(call.engine.setAppInBackground(false));

        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.backend.captures, hasLength(2));
        expect(call.backend.releasedPlaceholders, call.backend.placeholders);
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, capabilities: androidCapabilities);
    });

    test('a video call joined in the background where the camera would keep '
        'running never leaves it on', () {
      inCall((call) {
        call.wait(call.engine.setAppInBackground(true));
        call.joinEncrypted();

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(call.local.videoStream, isNull);
        expect(
          call.backend.streams.where((s) => s.id == 'local_video'),
          everyElement(
            isA<FakeMediaStream>().having((s) => s.disposed, 'disposed', true),
          ),
        );
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);

        call.wait(call.engine.setAppInBackground(false));

        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, capabilities: androidCapabilities);
    });

    test('a video call joined in the background starts on the placeholder '
        'and shows the camera once the app opens', () {
      inCall((call) {
        call.wait(call.engine.setAppInBackground(true));
        call.joinEncrypted();

        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);

        call.wait(call.engine.setAppInBackground(false));

        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, capabilities: iosCapabilities);
    });

    for (final (platform, capabilities) in [
      ('android', androidCapabilities),
      ('ios', iosCapabilities),
    ]) {
      test('on $platform, a camera that was off stays off when the app '
          'returns', () {
        inCall((call) {
          call.joinEncrypted();
          call.wait(call.engine.setCameraEnabled(false));

          call.wait(call.engine.setAppInBackground(true));
          call.wait(call.engine.setAppInBackground(false));

          expect(call.videoSlot.sender.track, placeholderOf(call));
          expect(call.backend.captures, hasLength(1));
          expect(call.local.videoEnabled, isFalse);
          expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
        }, capabilities: capabilities);
      });
    }
  });

  group('before joining', () {
    test('muting joins with the microphone off', () {
      inCall((call) {
        call.wait(call.engine.setMicrophoneMuted(true));
        expect(call.local.audioMuted, isTrue);

        call.joinEncrypted();

        expect(call.microphone.enabled, isFalse);
        expect(call.engine.localFociInfo?['audioMuted'], isTrue);
      }, kind: CallKind.voice);
    });

    test('turning the camera off joins with the microphone only, on the '
        'placeholder', () {
      inCall((call) {
        call.wait(call.engine.setCameraEnabled(false));
        expect(call.local.videoEnabled, isFalse);

        call.joinEncrypted();

        expect(call.backend.captureConstraints, [
          {'audio': true, 'video': false},
        ]);
        expect(call.videoSlot.sender.track, placeholderOf(call));
        expect(call.local.videoEnabled, isFalse);
      });
    });

    test('switching camera opens the back camera when joining', () {
      inCall((call) {
        call.wait(call.engine.switchCamera());
        expect(call.local.frontCamera, isFalse);

        call.joinEncrypted();

        final video = call.backend.captureConstraints.single['video'] as Map;
        expect(video['facingMode'], 'environment');
        expect(call.local.frontCamera, isFalse);
      });
    });

    test('switching to video opens the camera at once, and joining sends it '
        'without opening another', () {
      inCall((call) {
        call.wait(call.engine.switchToVideo());

        expect(call.backend.captureConstraints.single['audio'], isFalse);
        expect(call.backend.captureConstraints.single['video'], isA<Map>());
        expect(call.engine.kind, CallKind.video);

        call.joinEncrypted();

        expect(call.backend.captureConstraints.last, {
          'audio': true,
          'video': false,
        });
        expect(call.videoSlot.sender.track, same(call.camera));
        call.mediaFlows();
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, kind: CallKind.voice);
    });

    test('a camera that will not open keeps the call to voice', () {
      inCall((call) {
        call.backend.captureError = StateError('Camera denied');

        expect(
          () => call.wait(call.engine.switchToVideo()),
          throwsA(isA<StateError>()),
        );
        call.backend.captureError = null;
        call.joinEncrypted();

        expect(call.engine.kind, CallKind.voice);
        expect(call.local.videoEnabled, isFalse);
        expect(call.backend.captureConstraints.last, {
          'audio': true,
          'video': false,
        });
      }, kind: CallKind.voice);
    });

    test('turning the camera off and on while joining captures leaves one '
        'camera open, and sends it', () {
      inCall((call) {
        final gate = Completer<void>();
        call.backend.captureGate = gate;
        final joining = call.engine.join();
        call.flush();

        final off = call.engine.setCameraEnabled(false);
        final on = call.engine.setCameraEnabled(true);
        gate.complete();
        call.wait(joining);
        call.wait(off);
        call.wait(on);
        call.encrypt();

        final cameras = [
          for (final stream in call.backend.streams)
            if (stream.id == 'local_video' && !stream.disposed) stream,
        ];
        expect(cameras, hasLength(1));
        expect(call.videoSlot.sender.track, same(call.camera));
      });
    });
  });

  group('while the connection is being set up', () {
    test('a switch to video asked for while joining turns the camera on '
        'once published', () {
      inCall((call) {
        final gate = Completer<void>();
        call.sfu.sessionGate = gate;
        final joining = call.engine.join();
        call.flush();

        final switching = call.engine.switchToVideo();
        call.flush();
        gate.complete();
        call.wait(joining);
        call.wait(switching);

        expect(call.engine.kind, CallKind.video);
        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, kind: CallKind.voice);
    });

    test('a switch to video during a reconnect lands on the new '
        'connection', () {
      inCall((call) {
        call.joinEncrypted();
        final gate = Completer<void>();
        call.sfu.sessionGate = gate;
        call.engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();

        final switching = call.engine.switchToVideo();
        call.flush();
        gate.complete();
        call.wait(switching);
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(call.engine.kind, CallKind.video);
        expect(call.videoSlot.sender.track, same(call.camera));
        expect(call.engine.localFociInfo?['videoEnabled'], isTrue);
      }, kind: CallKind.voice);
    });
  });

  group('what shows up in the logs', () {
    late List<String> logs;

    setUp(() => logs = recordDebugPrints());

    Iterable<String> caught(List<String> logs) =>
        logs.where((l) => l.startsWith('zuno/caught:'));

    test('a placeholder the platform cannot make is left to the platform to '
        'report, and its silent video slot is not reported either', () {
      inCall((call) {
        call.backend.placeholderAvailable = false;

        call.join();
        call.mediaFlows(kinds: {'audio'});
        call.async.elapse(const Duration(seconds: 40));

        expect(caught(logs), isEmpty);
      }, kind: CallKind.voice);
    });

    test('a placeholder that fails to be made is reported once, for what '
        'failed', () {
      inCall((call) {
        call.backend.placeholderError = StateError('no placeholder');

        call.join();
        call.mediaFlows(kinds: {'audio'});
        call.async.elapse(const Duration(seconds: 40));

        expect(caught(logs), [
          'zuno/caught: create placeholder video: Bad state: no placeholder',
        ]);
      }, kind: CallKind.voice);
    });

    test('without a placeholder, a camera turned on that sends nothing is '
        'still reported', () {
      inCall((call) {
        call.backend.placeholderAvailable = false;
        call.join();
        call.wait(call.engine.setCameraEnabled(true));

        call.mediaFlows(kinds: {'audio'});
        call.async.elapse(const Duration(seconds: 40));

        expect(
          caught(
            logs,
          ).where((l) => l.contains('publish video') && l.contains('no media')),
          hasLength(1),
        );
      }, kind: CallKind.voice);
    });

    test('a track still silent 20 s after publishing, once', () {
      inCall((call) {
        call.join();
        call.mediaFlows(kinds: {'audio'});

        call.async.elapse(const Duration(seconds: 40));

        expect(
          logs.where(
            (l) => l.contains('publish video') && l.contains('no media'),
          ),
          hasLength(1),
        );
        expect(logs.where((l) => l.contains('publish audio')), isEmpty);
      }, kind: CallKind.voice);
    });

    test('a pull the SFU cannot find, once rather than on every retry', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu.missingTracks.add('video');

        call.remoteJoins();
        call.remoteJoins();

        expect(
          logs.where(
            (l) =>
                l.contains('pull video') && l.contains('not_found_track_error'),
          ),
          hasLength(1),
        );
      });
    });
  });
}
