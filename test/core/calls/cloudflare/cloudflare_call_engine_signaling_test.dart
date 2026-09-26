import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_api_client.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

import '../../../helpers/fake_webrtc.dart';
import 'cloudflare_engine_harness.dart';

void main() {
  void inCall(
    void Function(EngineHarness call) body, {
    CallKind kind = CallKind.voice,
    bool lowDataMode = false,
  }) {
    fakeAsync((async) {
      final call = EngineHarness(async, kind: kind, lowDataMode: lowDataMode);
      body(call);
      call.leave();
      call.flush();
    });
  }

  RTCRtpEncoding encoding(FakeSender sender) =>
      sender.appliedParameters.last.encodings!.first;

  group('joining', () {
    test('a voice call captures the microphone only, publishes audio plus an '
        'empty video slot, and applies the SFU answer', () {
      inCall((call) {
        call.join();

        expect(call.backend.captureConstraints, [
          {'audio': true, 'video': false},
        ]);
        expect(call.pc.configuration, {
          'iceServers': EngineHarness.iceServers,
          'sdpSemantics': 'unified-plan',
        });
        final [audio, video] = call.pc.rtpTransceivers;
        expect(audio.sender.track, call.microphone);
        expect(audio.direction, TransceiverDirection.SendOnly);
        expect(video.sender.track, isNull);
        expect(video.direction, TransceiverDirection.SendOnly);

        final push = call.sfu.pushes.single;
        expect(push.path, '/sessions/s1/tracks/new');
        expect(push.sessionDescription, {
          'sdp': 'local offer 1',
          'type': 'offer',
        });
        expect(push.tracks, [
          {'location': 'local', 'mid': '0', 'trackName': 'audio'},
          {'location': 'local', 'mid': '1', 'trackName': 'video'},
        ]);
        expect(call.pc.remoteDescriptions.single.sdp, 'sfu answer 1');
        expect(call.engine.status, CallEngineStatus.connected);
        expect(call.engine.localFociInfo, {
          'sessionId': 's1',
          'tracks': {'audio': 'audio', 'video': 'video'},
          'audioMuted': false,
          'videoEnabled': false,
          'encrypted': false,
          'lowBandwidth': false,
        });
      });
    });

    test('nothing leaves the phone unencrypted: the microphone stays off '
        'until the call key arrives', () {
      inCall((call) {
        call.join();
        expect(call.microphone.enabled, isFalse);
        expect(call.local.encrypted, isFalse);

        call.encrypt();

        expect(call.backend.cryptors.keyProviders.single.sharedKeys, [
          callKey(),
        ]);
        expect(call.backend.cryptors.liveLabels, {'local-audio'});
        expect(call.backend.cryptors.live.single.isEnabled, isTrue);
        expect(call.microphone.enabled, isTrue);
        expect(call.local.encrypted, isTrue);
        expect(call.engine.localFociInfo?['encrypted'], isTrue);
        expect(call.localStateChanges, greaterThan(0));
      });
    });

    test('a call key that cannot be applied leaves nothing half-encrypted', () {
      inCall((call) {
        call.join();
        call.backend.cryptors.failEnableFor.add('local-video');

        expect(call.encrypt, throwsA(isA<StateError>()));

        expect(call.backend.cryptors.live, isEmpty);
        expect(call.backend.cryptors.keyProviders.single.disposed, isTrue);
        expect(call.microphone.enabled, isFalse);
        expect(call.camera.enabled, isFalse);
        expect(call.local.encrypted, isFalse);
      }, kind: CallKind.video);
    });

    test(
      'a key that arrives first encrypts both senders as they are added',
      () {
        inCall((call) {
          call.encrypt();
          call.join();

          expect(call.backend.cryptors.liveLabels, {
            'local-audio',
            'local-video',
          });
          expect(call.microphone.enabled, isTrue);
          expect(call.camera.enabled, isTrue);
        }, kind: CallKind.video);
      },
    );

    for (final (lowData, width, height, fps, bitrate) in [
      (false, 854, 480, 30, 800000),
      (true, 640, 360, 24, 500000),
    ]) {
      test('a video call${lowData ? ' in low data mode' : ''} captures the '
          'camera at ${width}x$height, $fps fps, prefers VP8 then H264, and '
          'caps the encoder at $bitrate bps', () {
        inCall(
          (call) {
            call.join();

            expect(call.backend.captureConstraints.single['video'], {
              'facingMode': 'user',
              'width': width,
              'height': height,
              'frameRate': fps,
            });
            expect(call.videoSlot.sender.track, call.camera);
            expect(call.videoSlot.codecPreferences!.map((c) => c.mimeType), [
              'video/VP8',
              'video/H264',
              'video/AV1',
            ]);
            final limits = encoding(call.videoSlot.sender);
            expect(limits.maxBitrate, bitrate);
            expect(limits.maxFramerate, fps);
            expect(limits.scaleResolutionDownBy, 1.0);
            expect(call.local.frontCamera, isTrue);
          },
          kind: CallKind.video,
          lowDataMode: lowData,
        );
      });
    }
  });

  group('joining fails', () {
    test('an SFU that refuses a session fails the join and releases the '
        'capture and the connection', () {
      inCall((call) {
        call.sfu.sessionStatus = 500;

        expect(call.join, throwsA(isA<CloudflareCallsException>()));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.backend.captures.single.disposed, isTrue);
        expect(call.pc.closed, isTrue);
        expect(call.sfu.pushes, isEmpty);
      });
    });

    test('a refused microphone fails the join, and leaving closes the '
        'connection it opened', () {
      inCall((call) {
        call.backend.captureError = StateError('Permission denied');

        expect(call.join, throwsA(isA<StateError>()));
        expect(call.engine.status, CallEngineStatus.failed);

        call.leave();
        expect(call.pc.closed, isTrue);
        expect(call.pc.disposed, isTrue);
      });
    });

    test('leaving while the camera is still opening discards the capture and '
        'publishes nothing', () {
      inCall((call) {
        final gate = Completer<void>();
        call.backend.captureGate = gate;
        final joining = call.engine.join();
        call.flush();

        call.leave();
        gate.complete();
        call.wait(joining);

        expect(call.backend.captures.single.disposed, isTrue);
        expect(call.sfu.pushes, isEmpty);
        expect(call.pc.closed, isTrue);
      }, kind: CallKind.video);
    });
  });

  group('the other side', () {
    test('an encrypted participant is pulled, answered and decrypted, and '
        'their media reaches the screen', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        final pull = call.sfu.pulls.single;
        expect(pull.path, '/sessions/s1/tracks/new');
        expect(
          pull.tracks.map(
            (t) => (t['location'], t['sessionId'], t['trackName']),
          ),
          [('remote', 'remote-1', 'audio'), ('remote', 'remote-1', 'video')],
        );
        expect(call.pc.remoteDescriptions.last.sdp, 'sfu offer 1');
        expect(call.sfu.renegotiations.single.sessionDescription, {
          'sdp': 'local answer 1',
          'type': 'answer',
        });
        expect(
          call.backend.cryptors.liveLabels,
          containsAll([
            receiverLabel(ann, 'audio'),
            receiverLabel(ann, 'video'),
          ]),
        );

        final video = FakeMediaStream('ann-video');
        call.pc.emitTrack(call.pulledMids('video').single, video);
        call.flush();

        expect(call.remote()!.videoStream, video);
        expect(call.remote()!.encrypted, isTrue);
        expect(call.emitted.last.map((p) => p.id), contains(ann));
      });
    });

    test('no one is pulled until both sides encrypt', () {
      inCall((call) {
        call.join();
        call.remoteJoins();
        expect(call.sfu.pulls, isEmpty);

        call.encrypt();
        call.flush();
        expect(call.sfu.pulls, hasLength(1));
      });
    });

    test('someone not yet encrypted is not pulled until they are', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins(encrypted: false);
        expect(call.sfu.pulls, isEmpty);

        call.remoteJoins();
        expect(call.sfu.pulls, hasLength(1));
      });
    });

    test('a camera that is off is not pulled; turning it on pulls it', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins(videoEnabled: false);
        expect(call.sfu.pulls.single.tracks.map((t) => t['trackName']), [
          'audio',
        ]);

        call.remoteJoins();
        expect(call.sfu.pulls.last.tracks.map((t) => t['trackName']), [
          'video',
        ]);
      });
    });

    test('an unchanged membership pulls nothing again', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        call.remoteJoins();

        expect(call.sfu.pulls, hasLength(1));
      });
    });

    test('someone leaving closes their tracks on the SFU and drops their '
        'decryptors', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        final mids = [...call.pulledMids('audio'), ...call.pulledMids('video')];

        call.engine.removeRemoteParticipant(ann);
        call.flush();

        final close = call.sfu.closes.single;
        expect(close.path, '/sessions/s1/tracks/close');
        expect(close.tracks.map((t) => t['mid']), unorderedEquals(mids));
        expect(close.body!['force'], isFalse);
        expect(call.remote(), isNull);
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(ann, 'audio'))),
        );
      });
    });

    test('a new session from the same person closes the old tracks and pulls '
        'the new ones', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        call.remoteJoins(sessionId: 'remote-2');

        expect(call.sfu.closes, hasLength(1));
        expect(call.sfu.pulls, hasLength(2));
        expect(call.sfu.pulls.last.tracks.map((t) => t['sessionId']).toSet(), {
          'remote-2',
        });
      });
    });

    test('a pull the SFU never hears answered is forgotten, closed on the '
        'SFU, and pulled again on the next update', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu.renegotiateStatus = 500;
        call.remoteJoins();
        final halfPulled = [
          ...call.pulledMids('audio'),
          ...call.pulledMids('video'),
        ];

        final close = call.sfu.closes.single;
        expect(close.tracks.map((t) => t['mid']), unorderedEquals(halfPulled));
        expect(close.body!['force'], isTrue);
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(ann, 'audio'))),
        );

        call.sfu.renegotiateStatus = null;
        call.remoteJoins();

        expect(call.sfu.pulls, hasLength(2));
        expect(call.sfu.renegotiations, hasLength(2));
        final video = FakeMediaStream('ann-video');
        call.pc.emitTrack(call.pulledMids('video').last, video);
        call.flush();
        expect(call.remote()!.videoStream, video);
      });
    });

    test('an SFU offer that cannot be applied is forgotten and pulled again '
        'on the next update', () {
      inCall((call) {
        call.joinEncrypted();
        call.pc.setRemoteDescriptionError = StateError('bad offer');
        call.remoteJoins();
        expect(call.sfu.renegotiations, isEmpty);

        call.pc.setRemoteDescriptionError = null;
        call.remoteJoins();

        expect(call.sfu.pulls, hasLength(2));
        expect(call.sfu.renegotiations, hasLength(1));
      });
    });

    test('an offer we cannot answer is rolled back, so the connection is not '
        'left waiting', () {
      inCall((call) {
        call.joinEncrypted();
        call.pc.createAnswerError = StateError('no answer');
        call.remoteJoins();

        expect(call.pc.localDescriptions.last.type, 'rollback');
        expect(
          call.pc.signalingState,
          RTCSignalingState.RTCSignalingStateStable,
        );

        call.pc.createAnswerError = null;
        call.remoteJoins();
        expect(call.sfu.renegotiations, hasLength(1));
      });
    });

    test('closing tracks the SFU wants renegotiated applies its offer and '
        'answers it', () {
      inCall((call) {
        call.sfu.closeRenegotiates = true;
        call.joinEncrypted();
        call.remoteJoins();

        call.engine.removeRemoteParticipant(ann);
        call.flush();

        expect(call.pc.remoteDescriptions.last.sdp, 'sfu close offer');
        expect(call.sfu.renegotiations, hasLength(2));
        expect(
          call.sfu.renegotiations.last.sessionDescription?['type'],
          'answer',
        );
      });
    });

    test(
      'an update that arrives mid-pull is applied once the pull finishes',
      () {
        inCall((call) {
          call.joinEncrypted();
          final gate = Completer<void>();
          call.sfu.pullGate = gate;
          call.remoteJoins(videoEnabled: false);

          call.remoteJoins();
          expect(call.sfu.pulls, hasLength(1));

          gate.complete();
          call.flush();

          expect(call.sfu.pulls.map((p) => p.tracks.single['trackName']), [
            'audio',
            'video',
          ]);
        });
      },
    );

    test('a track re-pulled onto a slot that already exists is picked up '
        'without waiting for a track event', () {
      inCall((call) {
        call.sfu.reuseMids = true;
        call.joinEncrypted();
        call.remoteJoins();
        expect(call.remote()!.videoStream, isNull);

        call.remoteJoins(sessionId: 'remote-2');

        final adopted = call.remote()!.videoStream as FakeMediaStream?;
        expect(adopted, isNotNull);
        expect(
          adopted!.getVideoTracks().single,
          call.pc.transceiverFor(call.pulledMids('video').last).receiver.track,
        );
      });
    });
  });

  group('during the call', () {
    test('mute switches the microphone off and says so; unmute turns it back '
        'on', () {
      inCall((call) {
        call.joinEncrypted();

        call.wait(call.engine.setMicrophoneMuted(true));
        expect(call.microphone.enabled, isFalse);
        expect(call.local.audioMuted, isTrue);
        expect(call.engine.localFociInfo?['audioMuted'], isTrue);

        call.wait(call.engine.setMicrophoneMuted(false));
        expect(call.microphone.enabled, isTrue);
      });
    });

    test('turning the camera off stops sending frames and says so', () {
      inCall((call) {
        call.joinEncrypted();

        call.wait(call.engine.setCameraEnabled(false));

        expect(call.camera.enabled, isFalse);
        expect(call.engine.localFociInfo?['videoEnabled'], isFalse);
      }, kind: CallKind.video);
    });

    test('a voice call turned into video fills the empty video slot, '
        'encrypted, without renegotiating', () {
      inCall((call) {
        call.joinEncrypted();

        call.wait(call.engine.switchToVideo());

        expect(call.backend.captureConstraints.last, {
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': 854,
            'height': 480,
            'frameRate': 30,
          },
        });
        expect(call.videoSlot.sender.replacedTracks, [call.camera]);
        expect(call.backend.cryptors.liveLabels, contains('local-video'));
        expect(call.camera.enabled, isTrue);
        expect(call.engine.kind, CallKind.video);
        expect(call.local.videoEnabled, isTrue);
        expect(call.sfu.pushes, hasLength(1));
      });
    });

    test('a video switch whose encryption fails leaves the call a voice call '
        'and releases the camera', () {
      inCall((call) {
        call.joinEncrypted();
        call.backend.cryptors.failEnableFor.add('local-video');

        expect(
          () => call.wait(call.engine.switchToVideo()),
          throwsA(isA<StateError>()),
        );

        expect(call.engine.kind, CallKind.voice);
        expect(call.local.videoEnabled, isFalse);
        expect(call.local.videoStream, isNull);
        expect(call.backend.captures.last.disposed, isTrue);
      });
    });

    test('switching camera reports which side is in use', () {
      inCall((call) {
        call.join();

        call.wait(call.engine.switchCamera());

        expect(call.backend.cameraSwitches, 1);
        expect(call.local.frontCamera, isFalse);
      }, kind: CallKind.video);
    });
  });

  group('connection trouble', () {
    test('a failed connection rejoins on a new session, republishes, re-pulls '
        'everyone and re-encrypts', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        final firstPc = call.pc;
        final changesBefore = call.localStateChanges;

        call.engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(firstPc.closed, isTrue);
        expect(call.sfu.pushes.last.path, '/sessions/s2/tracks/new');
        expect(call.sfu.pulls.last.path, '/sessions/s2/tracks/new');
        expect(call.engine.localFociInfo?['sessionId'], 's2');
        expect(call.localStateChanges, greaterThan(changesBefore));
        expect(call.backend.cryptors.liveLabels, contains('local-audio'));
        expect(
          call.backend.cryptors.cryptors
              .where((c) => c.participantId == 'local-audio')
              .first
              .disposed,
          isTrue,
        );
        expect(call.statuses, contains(CallEngineStatus.reconnecting));
      });
    });
  });

  group('leaving mid-rejoin', () {
    test('leaving while a rejoin is still opening its connection closes that '
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
        expect(call.backend.peerConnections, hasLength(2));

        call.leave();
        gate.complete();
        call.flush();

        expect(call.backend.peerConnections.last.closed, isTrue);
        expect(call.sfu.pushes, hasLength(1));
        expect(call.engine.status, CallEngineStatus.disconnected);
      });
    });
  });

  group('call quality', () {
    StatsReport inbound(int lost, int received) => StatsReport(
      'in',
      'inbound-rtp',
      0,
      {'packetsLost': lost, 'packetsReceived': received},
    );

    test(
      'sustained packet loss lowers the video encoding and tells everyone',
      () {
        inCall((call) {
          call.joinEncrypted();
          final sender = call.videoSlot.sender;
          final changesBefore = call.localStateChanges;

          for (final (lost, received) in [
            (0, 1000),
            (100, 1900),
            (200, 2800),
          ]) {
            call.pc.stats = [inbound(lost, received)];
            call.async.elapse(const Duration(seconds: 3));
            call.flush();
          }

          expect(encoding(sender).maxBitrate, 300000);
          expect(encoding(sender).scaleResolutionDownBy, 2.0);
          expect(call.local.lowBandwidth, isTrue);
          expect(call.engine.localFociInfo?['lowBandwidth'], isTrue);
          expect(call.localStateChanges, greaterThan(changesBefore));
        }, kind: CallKind.video);
      },
    );

    test('a single bad sample changes nothing', () {
      inCall((call) {
        call.joinEncrypted();
        final applied = call.videoSlot.sender.appliedParameters.length;

        for (final (lost, received) in [(0, 1000), (100, 1900)]) {
          call.pc.stats = [inbound(lost, received)];
          call.async.elapse(const Duration(seconds: 3));
          call.flush();
        }

        expect(call.videoSlot.sender.appliedParameters, hasLength(applied));
        expect(call.local.lowBandwidth, isFalse);
      }, kind: CallKind.video);
    });

    test('someone on a weak link lowers our video too', () {
      inCall((call) {
        call.joinEncrypted();

        call.remoteJoins(lowBandwidth: true);

        expect(encoding(call.videoSlot.sender).maxBitrate, 300000);
      }, kind: CallKind.video);
    });
  });

  group('leaving', () {
    test('leaving releases every decryptor, the key, the capture and the '
        'connection', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        call.leave();

        expect(call.backend.cryptors.live, isEmpty);
        expect(call.backend.cryptors.keyProviders.single.disposed, isTrue);
        expect(
          call.backend.streams.where((s) => s.id.startsWith('local_')),
          everyElement(predicate<FakeMediaStream>((s) => s.disposed)),
        );
        expect(call.pc.closed, isTrue);
        expect(call.pc.disposed, isTrue);
        expect(call.engine.status, CallEngineStatus.disconnected);
        expect(call.engine.participants.where((p) => !p.isLocal), isEmpty);
        expect(call.engine.localFociInfo, isNull);
      }, kind: CallKind.video);
    });
  });
}
