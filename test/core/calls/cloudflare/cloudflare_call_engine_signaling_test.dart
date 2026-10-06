import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_api_client.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_webrtc.dart';
import '../../../helpers/platform_capabilities.dart';
import 'cloudflare_engine_harness.dart';

void main() {
  void inCall(
    void Function(EngineHarness call) body, {
    CallKind kind = CallKind.voice,
    bool lowDataMode = false,
    PlatformCapabilities? capabilities,
  }) {
    fakeAsync((async) {
      final call = EngineHarness(
        async,
        kind: kind,
        lowDataMode: lowDataMode,
        capabilities: capabilities,
      );
      body(call);
      call.leave();
      call.flush();
    });
  }

  RTCRtpEncoding encoding(FakeSender sender) =>
      sender.appliedParameters.last.encodings!.first;

  group('joining', () {
    test('a voice call captures the microphone only, publishes audio plus a '
        'black placeholder video, and applies the SFU answer', () {
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
        expect(video.sender.track, call.backend.placeholders.single.track);
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
        call.mediaFlows();
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
        expect(call.backend.cryptors.liveLabels, {
          'local-audio',
          'local-video',
        });
        expect(call.backend.cryptors.live.every((c) => c.isEnabled), isTrue);
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
      (false, 854, 480, 30, 950000),
      (true, 640, 360, 30, 500000),
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

    test(
      'without a placeholder, a voice call publishes an empty video slot',
      () {
        inCall((call) {
          call.backend.placeholderAvailable = false;

          call.join();

          expect(call.videoSlot.sender.track, isNull);
          expect(call.sfu.pushes.single.tracks, [
            {'location': 'local', 'mid': '0', 'trackName': 'audio'},
            {'location': 'local', 'mid': '1', 'trackName': 'video'},
          ]);
        });
      },
    );

    test('a video call publishes camera and microphone together', () {
      inCall((call) {
        call.join();
        call.mediaFlows();

        expect(call.sfu.pushes.single.tracks, [
          {'location': 'local', 'mid': '0', 'trackName': 'audio'},
          {'location': 'local', 'mid': '1', 'trackName': 'video'},
        ]);
        expect(call.engine.localFociInfo?['tracks'], {
          'audio': 'audio',
          'video': 'video',
        });
      }, kind: CallKind.video);
    });

    test('a track is offered to others only once it has sent media, so no '
        'one pulls it before the SFU has it', () {
      inCall((call) {
        call.join();
        final changes = call.localStateChanges;

        expect(call.engine.localFociInfo?['tracks'], isEmpty);

        call.mediaFlows(kinds: {'audio'});

        expect(call.engine.localFociInfo?['tracks'], {'audio': 'audio'});
        expect(call.localStateChanges, greaterThan(changes));

        call.mediaFlows();

        expect(call.engine.localFociInfo?['tracks'], {
          'audio': 'audio',
          'video': 'video',
        });
      });
    });

    test('publishing asks for no receive-only slots, so each pull brings its '
        'own', () {
      inCall((call) {
        call.join();

        expect(call.pc.offerConstraints, [<String, dynamic>{}]);
      });
    });

    test('a video call has the encoder keep its frame rate when it adapts', () {
      inCall((call) {
        call.join();

        expect(
          call.videoSlot.sender.parameters.degradationPreference,
          RTCDegradationPreference.MAINTAIN_FRAMERATE,
        );
      }, kind: CallKind.video);
    });
  });

  group('video codec order', () {
    test('where the platform sets one, the camera sender prefers it', () {
      inCall(
        (call) {
          call.join();

          expect(
            call.videoSlot.codecPreferences!.map((c) => c.mimeType).take(2),
            ['video/VP8', 'video/H264'],
          );
        },
        kind: CallKind.video,
        capabilities: androidCapabilities,
      );
    });

    test('where the platform keeps WebRTC\'s own order, none is set and the '
        'call still publishes its camera', () {
      inCall(
        (call) {
          call.join();

          expect(call.videoSlot.codecPreferences, isNull);
          expect(call.videoSlot.sender.track, call.camera);
        },
        kind: CallKind.video,
        capabilities: iosCapabilities,
      );
    });
  });

  group('microphone mute mode', () {
    test('where a voice-processing mute would outlast the call, the call '
        'mutes with its own input mixer, set before the microphone opens', () {
      inCall((call) {
        call.join();

        expect(call.backend.muteModes, [
          (mode: MicrophoneMuteMode.inputMixer, capturesBefore: 0),
        ]);
      }, capabilities: iosCapabilities);
    });

    test('elsewhere the mute mode is left alone', () {
      inCall((call) {
        call.join();

        expect(call.backend.muteModes, isEmpty);
      }, capabilities: androidCapabilities);
    });
  });

  group('system call audio', () {
    test('under CallKit the audio gate is armed before the microphone or the '
        'connection opens', () {
      inCall((call) {
        call.join();

        expect(call.backend.audioArms, [
          (capturesBefore: 0, connectionsBefore: 0),
        ]);
      }, capabilities: iosCapabilities);
    });

    test('without CallKit nothing is armed', () {
      inCall((call) {
        call.join();

        expect(call.backend.audioArms, isEmpty);
      }, capabilities: androidCapabilities);
    });
  });

  group('our voice', () {
    test('goes out with in-band FEC and no silence suppression, so a muted '
        'microphone keeps its track alive on the SFU', () {
      inCall((call) {
        call.sfu.answerSdp = opusSdp('minptime=10;useinbandfec=1');

        call.join();

        expect(
          call.pc.remoteDescriptions.single.sdp,
          contains('a=fmtp:111 minptime=10;useinbandfec=1;usedtx=0\r\n'),
        );
      });
    });

    test('keeps those settings when someone is pulled in', () {
      inCall((call) {
        call.sfu.offerSdp = opusSdp('minptime=10');
        call.joinEncrypted();

        call.remoteJoins();

        expect(
          call.pc.remoteDescriptions.last.sdp,
          contains('a=fmtp:111 minptime=10;useinbandfec=1;usedtx=0\r\n'),
        );
      });
    });
  });

  group('joining fails', () {
    test('an SFU that refuses a session fails the join and releases the '
        'capture and the connection', () {
      inCall((call) {
        call.sfu.sessionStatus = 500;

        expect(call.join, throwsA(isA<CloudflareCallsException>()));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.backend.captures.single.disposed, isTrue);
        expect(call.pc.disposed, isTrue);
        expect(call.sfu.pushes, isEmpty);
      });
    });

    test('a refused microphone fails the join, and leaving disposes the '
        'connection it opened in one step, never closing it first', () {
      inCall((call) {
        call.backend.captureError = StateError('Permission denied');

        expect(call.join, throwsA(isA<StateError>()));
        expect(call.engine.status, CallEngineStatus.failed);

        call.leave();
        expect(call.pc.disposed, isTrue);
        expect(call.pc.closed, isFalse);
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
        expect(call.pc.disposed, isTrue);
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

    test('a voice call turned into video swaps the black placeholder for the '
        'camera, encrypted, without renegotiating, and releases it', () {
      inCall((call) {
        call.joinEncrypted();

        call.wait(call.engine.switchToVideo());

        expect(call.backend.placeholders, hasLength(1));
        expect(call.backend.releasedPlaceholders, call.backend.placeholders);

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
        expect(
          call.emitted.last.singleWhere((p) => p.isLocal).videoEnabled,
          isTrue,
        );
        expect(call.sfu.pushes, hasLength(1));
      });
    });

    test('without a placeholder, a video switch whose encryption fails leaves '
        'the call a voice call and releases the camera', () {
      inCall((call) {
        call.backend.placeholderAvailable = false;
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
        expect(firstPc.disposed, isTrue);
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

    test('after a rejoin, tracks are offered again only once the new '
        'connection sends media', () {
      inCall((call) {
        call.joinEncrypted();
        call.mediaFlows();

        call.engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();

        expect(call.engine.localFociInfo?['sessionId'], 's2');
        expect(call.engine.localFociInfo?['tracks'], isEmpty);

        call.mediaFlows();

        expect(call.engine.localFociInfo?['tracks'], {
          'audio': 'audio',
          'video': 'video',
        });
      });
    });

    test('a rejoin puts the same black placeholder on the new connection', () {
      inCall((call) {
        call.joinEncrypted();

        call.engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(
          call.videoSlot.sender.track,
          call.backend.placeholders.single.track,
        );
        expect(call.backend.releasedPlaceholders, isEmpty);
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

        expect(call.backend.peerConnections.last.disposed, isTrue);
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
          expect(encoding(sender).maxFramerate, 30);
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

    test('loss while a newly pulled stream starts up does not mark the '
        'connection weak', () {
      inCall((call) {
        call.joinEncrypted();
        StatsReport pulled(int lost, int received) => StatsReport(
          'pulled',
          'inbound-rtp',
          0,
          {'packetsLost': lost, 'packetsReceived': received},
        );

        for (final stats in [
          [inbound(0, 1000)],
          [inbound(0, 1100), pulled(10, 90)],
          [inbound(0, 1200), pulled(20, 180)],
          [inbound(0, 1300), pulled(20, 280)],
        ]) {
          call.pc.stats = stats;
          call.async.elapse(const Duration(seconds: 3));
          call.flush();
        }

        expect(call.local.lowBandwidth, isFalse);
        expect(call.engine.localFociInfo?['lowBandwidth'], isFalse);
      }, kind: CallKind.video);
    });

    test('someone on a weak link lowers our video too', () {
      inCall((call) {
        call.joinEncrypted();

        call.remoteJoins(lowBandwidth: true);

        expect(encoding(call.videoSlot.sender).maxBitrate, 300000);
        expect(encoding(call.videoSlot.sender).maxFramerate, 30);
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
        expect(call.pc.disposed, isTrue);
        expect(call.pc.disposed, isTrue);
        expect(call.engine.status, CallEngineStatus.disconnected);
        expect(call.engine.participants.where((p) => !p.isLocal), isEmpty);
        expect(call.engine.localFociInfo, isNull);
      }, kind: CallKind.video);
    });

    test('leaving a voice call releases the black placeholder', () {
      inCall((call) {
        call.joinEncrypted();

        call.leave();

        expect(call.backend.placeholders, hasLength(1));
        expect(call.backend.releasedPlaceholders, call.backend.placeholders);
        expect(call.pc.disposed, isTrue);
      });
    });
  });
}
