import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/media/call_media_engine.dart';
import 'package:zuno/core/calls/media/simulcast_layers.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/module/calls_module.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_webrtc.dart';
import '../../../helpers/platform_capabilities.dart';
import 'cloudflare_engine_harness.dart';

void main() {
  late List<String> logs;

  setUp(() => logs = recordDebugPrints());

  Iterable<String> caught() =>
      logs.where((line) => line.startsWith('zuno/caught:'));

  void inCall(
    void Function(EngineHarness call) body, {
    CallKind kind = CallKind.voice,
    bool lowDataMode = false,
    PlatformCapabilities? capabilities,
  }) => runEngineCall(
    body,
    kind: kind,
    lowDataMode: lowDataMode,
    capabilities: capabilities,
  );

  StatsReport roundTrip(double seconds) =>
      candidatePair('pair', rttSeconds: seconds);

  List<List<StatsReport>> polls(int count, List<StatsReport> stats) => [
    for (var poll = 0; poll < count; poll++) stats,
  ];

  RTCRtpEncoding layer(FakeSender sender, String rid) =>
      sender.appliedParameters.last.encodings!.firstWhere((e) => e.rid == rid);

  group('joining', () {
    test('announces its local state as soon as its SFU session opens, before '
        'it publishes media, so a membership can carry the session', () {
      inCall((call) {
        Object? sessionThen;
        int? pushesThen;
        call.engine.localStateChangedStream.first.then((_) {
          sessionThen = call.engine.localFociInfo?['sessionId'];
          pushesThen = call.sfu.pushes.length;
        });

        call.join();

        expect(sessionThen, 's1');
        expect(pushesThen, 0);
      });
    });

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
        expect(video.sender.track, call.placeholders.created.single.track);
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
        });
      });
    });

    test('nothing leaves the phone unencrypted: the microphone stays off '
        'until our key is in place', () {
      inCall((call) {
        call.join();
        expect(call.microphone.enabled, isFalse);
        expect(call.local.encrypted, isFalse);

        call.encrypt();

        expect(call.backend.cryptors.keyProviders.first.slots, {1: keyBytes()});
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

    test('a sender that cannot be encrypted surfaces the error, its track '
        'stays off and everything sent is encrypted', () {
      inCall((call) {
        call.join();
        call.backend.cryptors.failEnableFor.add('local-video');

        expect(call.encrypt, throwsA(isA<StateError>()));

        expect(call.backend.cryptors.liveLabels, {'local-audio'});
        expect(call.backend.cryptors.live.every((c) => c.isEnabled), isTrue);
        expect(call.microphone.enabled, isTrue);
        expect(call.camera.enabled, isFalse);
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

    for (final (lowData, width, height, fps) in [
      (false, 854, 480, 30),
      (true, 640, 360, 30),
    ]) {
      test('a video call${lowData ? ' in low data mode' : ''} captures the '
          'camera at ${width}x$height, $fps fps, and sends its full layer '
          'at the layer set\'s limits', () {
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
            final full = layer(call.videoSlot.sender, 'h');
            final expected = simulcastLayersFor(lowDataMode: lowData).last;
            expect(full.maxBitrate, expected.maxBitrate);
            expect(full.maxFramerate, expected.maxFramerate);
            expect(full.scaleResolutionDownBy, expected.scaleResolutionDownBy);
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
          call.placeholders.available = false;

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

    test('a remote that joins while our media opens is pulled only once our '
        'tracks are published', () {
      inCall((call) {
        call.encrypt();
        final gate = Completer<void>();
        call.backend.captureGate = gate;
        final joining = joinWithLocalMedia(call.engine);
        call.flush();

        call.remoteJoins();
        expect(call.sfu.pulls, isEmpty);

        gate.complete();
        call.wait(joining);
        call.flush();

        expect(call.sfu.pulls, hasLength(1));
        expect(
          call.sfu.requests.indexOf(call.sfu.pushes.single),
          lessThan(call.sfu.requests.indexOf(call.sfu.pulls.single)),
        );
      });
    });

    test('a remote handed over before the session opens is pulled once the '
        'join has published', () {
      inCall((call) {
        call.encrypt();
        final gate = Completer<void>();
        call.sfu.sessionGate = gate;
        final joining = joinWithLocalMedia(call.engine);
        call.flush();

        call.remoteJoins();
        gate.complete();
        call.wait(joining);
        call.flush();

        expect(call.sfu.pulls, hasLength(1));
      });
    });

    test('a track is offered within a tenth of a second of its first '
        'media', () {
      inCall((call) {
        call.join();
        call.async.elapse(const Duration(milliseconds: 800));

        call.pc.stats = [
          EngineHarness.outbound('audio'),
          EngineHarness.outbound('video'),
        ];
        call.async.elapse(const Duration(milliseconds: 100));
        call.flush();

        expect(call.engine.localFociInfo?['tracks'], {
          'audio': 'audio',
          'video': 'video',
        });
      });
    });

    test('a track that never sends media is reported once, when the wait for '
        'its first media runs out', () {
      inCall((call) {
        call.join();
        call.pc.stats = [EngineHarness.outbound('audio')];

        call.async.elapse(const Duration(seconds: 19));
        call.flush();
        expect(caught().where((line) => line.contains('publish video')), []);

        call.async.elapse(const Duration(seconds: 10));
        call.flush();
        expect(
          caught().where((line) => line.contains('publish video')),
          hasLength(1),
        );
      });
    });

    test('stops asking for stats once every track sends media', () {
      inCall((call) {
        call.join();
        call.pc.stats = [
          EngineHarness.outbound('audio'),
          EngineHarness.outbound('video'),
        ];
        call.async.elapse(const Duration(milliseconds: 300));
        call.flush();
        final calls = call.pc.statsCalls;

        call.async.elapse(const Duration(milliseconds: 2500));
        call.flush();

        expect(call.pc.statsCalls, calls);
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

  group('video codec', () {
    const answer =
        'v=0\r\n'
        'o=- 1 2 IN IP4 127.0.0.1\r\n'
        's=-\r\n'
        't=0 0\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 102 96\r\n'
        'a=recvonly\r\n'
        'a=rtpmap:102 H264/90000\r\n'
        'a=rtpmap:96 VP8/90000\r\n';

    test('every phone sends VP8, whatever order Cloudflare\'s answer '
        'lists', () {
      inCall((call) {
        call.sfu.answerSdp = answer;

        call.join();

        expect(
          call.pc.remoteDescriptions.single.sdp,
          contains('m=video 9 UDP/TLS/RTP/SAVPF 96 102\r\n'),
        );
        expect(call.videoSlot.sender.track, call.camera);
      }, kind: CallKind.video);
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

  group('opening local media', () {
    test('before joining captures the microphone and camera at once, and '
        'joining publishes them without capturing again', () {
      inCall((call) {
        call.wait(call.engine.startLocalMedia());

        expect(call.backend.captureConstraints.single['audio'], isTrue);
        expect(call.backend.captureConstraints.single['video'], isA<Map>());
        expect(call.backend.peerConnections, isEmpty);
        expect(call.local.audioStream, isNotNull);
        expect(call.local.videoStream, isNotNull);
        final announced = call.emitted.last.singleWhere((p) => p.isLocal);
        expect(announced.audioStream, isNotNull);

        call.joinEncrypted();

        expect(call.backend.captureConstraints, hasLength(1));
        final [audio, video] = call.pc.rtpTransceivers;
        expect(audio.sender.track, call.microphone);
        expect(video.sender.track, same(call.camera));
      }, kind: CallKind.video);
    });

    test('under CallKit arms the audio gate before the microphone, '
        'once', () {
      inCall((call) {
        call.wait(call.engine.startLocalMedia());
        call.join();

        expect(call.backend.audioArms, [
          (capturesBefore: 0, connectionsBefore: 0),
        ]);
      }, capabilities: iosCapabilities);
    });

    test('leaving while it is still opening releases it', () {
      inCall((call) {
        final gate = Completer<void>();
        call.backend.captureGate = gate;
        final opening = call.engine.startLocalMedia();
        call.flush();

        call.leave();
        gate.complete();
        call.wait(opening);

        expect(call.backend.captures.single.disposed, isTrue);
        expect(call.local.audioStream, isNull);
      });
    });

    test('a hang-up before it reaches the microphone captures nothing', () {
      inCall((call) {
        final opening = call.engine.startLocalMedia();
        call.engine.leave();
        call.flush();
        call.wait(opening);

        expect(call.backend.captureConstraints, isEmpty);
      }, capabilities: iosCapabilities);
    });

    test('a capture it cannot take over is released, microphone and all', () {
      inCall((call) {
        call.backend.adoptErrors['local_video'] = StateError('no stream');

        expect(
          () => call.wait(call.engine.startLocalMedia()),
          throwsA(isA<StateError>()),
        );

        expect(call.backend.captures.single.disposed, isTrue);
        expect(call.backend.streams.single.id, 'local_audio');
        expect(call.backend.streams.single.disposed, isTrue);
        expect(call.local.audioStream, isNull);
      }, kind: CallKind.video);
    });

    test(
      'hanging up releases the capture behind the microphone and camera',
      () {
        inCall((call) {
          call.joinEncrypted();

          call.leave();

          expect(call.backend.captures, isNotEmpty);
          expect(
            call.backend.captures,
            everyElement(
              isA<FakeMediaStream>().having(
                (s) => s.disposed,
                'disposed',
                true,
              ),
            ),
          );
        }, kind: CallKind.video);
      },
    );

    test('opened in the background where the camera would keep running, it '
        'leaves the camera off until the app returns', () {
      inCall(
        (call) {
          call.wait(call.engine.setAppInBackground(true));

          call.wait(call.engine.startLocalMedia());

          expect(call.backend.captureConstraints.single['video'], isFalse);
          expect(call.local.videoStream, isNull);

          call.wait(call.engine.setAppInBackground(false));

          expect(call.backend.captureConstraints.last['video'], isA<Map>());
          expect(call.local.videoStream, isNotNull);
        },
        kind: CallKind.video,
        capabilities: androidCapabilities,
      );
    });

    test('opened in the background where the camera stops by itself, it '
        'captures the camera with the microphone', () {
      inCall(
        (call) {
          call.wait(call.engine.setAppInBackground(true));

          call.wait(call.engine.startLocalMedia());

          expect(call.backend.captureConstraints.single['video'], isA<Map>());
        },
        kind: CallKind.video,
        capabilities: iosCapabilities,
      );
    });
  });

  group('joining fails', () {
    test('not when the call is left while its media is being attached', () {
      inCall((call) {
        final gate = Completer<void>();
        call.backend.transceiverGate = gate;
        final joining = joinWithLocalMedia(call.engine);
        call.flush();

        call.leave();
        gate.complete();
        call.wait(joining);

        expect(call.statuses.last, CallEngineStatus.disconnected);
      });
    });

    test('an engine whose server address cannot be worked out still builds '
        'and opens local media, and fails only when it joins', () {
      fakeAsync((async) {
        final call = EngineHarness(
          async,
          baseUri: () => throw StateError('no homeserver'),
        );

        call.wait(call.engine.startLocalMedia());
        expect(call.local.audioStream, isNotNull);

        expect(call.join, throwsA(isA<StateError>()));
        expect(call.engine.status, CallEngineStatus.failed);

        call.leave();
        expect(call.backend.captures.single.disposed, isTrue);
      });
    });

    test('an SFU that refuses a session fails the join and releases the '
        'connection, and leaving releases the microphone', () {
      inCall((call) {
        call.sfu.sessionStatus = 500;

        expect(call.join, throwsA(isA<CallsModuleException>()));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.pc.disposed, isTrue);
        expect(call.sfu.pushes, isEmpty);

        call.leave();

        expect(call.backend.streams, isNotEmpty);
        expect(call.backend.streams.every((s) => s.disposed), isTrue);
      });
    });

    test('a call the module says is full fails the join with its limit, '
        'asked once', () {
      inCall((call) {
        call.sfu
          ..sessionStatus = 403
          ..sessionRefusal = {
            'errcode': 'IM.ZUNO.CALL_FULL',
            'error': 'This call is full',
            'max_participants': 8,
          };

        expect(
          call.join,
          throwsA(
            isA<CallFullException>().having(
              (e) => e.maxParticipants,
              'maxParticipants',
              8,
            ),
          ),
        );
        expect(call.engine.status, CallEngineStatus.failed);
        expect(
          call.sfu.requests.where((r) => r.path == '/sessions/new'),
          hasLength(1),
        );
        expect(call.sfu.pushes, isEmpty);
      });
    });

    test('joining a call we were removed from fails the join as removed, '
        'asked once and never reported', () {
      inCall((call) {
        call.sfu.removedFromCall = true;

        expect(call.join, throwsA(isA<CallRemovedException>()));
        expect(call.engine.status, CallEngineStatus.removed);
        expect(
          call.sfu.requests.where((r) => r.path == '/sessions/new'),
          hasLength(1),
        );
        expect(caught(), isEmpty);
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
        final joining = joinWithLocalMedia(call.engine);
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
            receiverLabel(ann, MediaKind.audio),
            receiverLabel(ann, MediaKind.video),
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
        expect(close.body!['force'], isTrue);
        expect(close.sessionDescription, isNull);
        expect(caught(), isEmpty);
        expect(call.remote(), isNull);
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(ann, MediaKind.audio))),
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

    final unfinishedPulls = <String, void Function(EngineHarness call)>{
      'the SFU refuses our answer': (call) => call.sfu.renegotiateStatus = 500,
      'its offer cannot be applied': (call) =>
          call.pc.setRemoteDescriptionError = StateError('bad offer'),
      'we cannot answer its offer': (call) =>
          call.pc.createAnswerError = StateError('no answer'),
      'its response is lost': (call) => call.sfu.lostPullResponses = 1,
    };
    for (final MapEntry(key: cause, value: breakPull)
        in unfinishedPulls.entries) {
      test('a pull left unfinished because $cause is never retried on that '
          'session: the call rejoins on a new one and pulls there', () {
        inCall((call) {
          call.joinEncrypted();
          breakPull(call);
          call.remoteJoins();
          call.remoteJoins();

          expect(call.sfu.pulls, hasLength(1));
          expect(call.sfu.closes, isEmpty);
          expect(call.engine.status, CallEngineStatus.reconnecting);

          call.sfu.renegotiateStatus = null;
          call.pc.setRemoteDescriptionError = null;
          call.pc.createAnswerError = null;
          call.async.elapse(const Duration(seconds: 2));
          call.flush();

          expect(call.sfu.pulls.last.path, '/sessions/s2/tracks/new');
          expect(call.sfu.renegotiations.last.path, '/sessions/s2/renegotiate');
          expect(
            call.sfu.requests.where((r) => r.path.contains('/s1/')),
            hasLength(cause == 'the SFU refuses our answer' ? 3 : 2),
          );
          final video = FakeMediaStream('ann-video');
          call.pc.emitTrack(call.pulledMids('video').last, video);
          call.flush();
          expect(call.remote()!.videoStream, video);
        });
      });
    }

    test('a pull that fails reports its own error, not a later pull\'s', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu.renegotiateStatus = 500;
        final gate = Completer<void>();
        call.sfu.pullGate = gate;
        call.remoteJoins();
        call.remoteJoins(videoEnabled: false);

        gate.complete();
        call.flush();

        expect(caught(), [
          startsWith(
            'zuno/caught: pull remote tracks: CallsModuleException: '
            'HTTP 500 from PUT /sessions/{id}/renegotiate',
          ),
        ]);
      });
    });

    test('a pull that fails on every new session ends the call after three '
        'rejoins rather than rejoining forever', () {
      inCall((call) {
        call.sfu.connectOnPush = true;
        call.joinEncrypted();
        call.sfu.renegotiateStatus = 500;
        call.remoteJoins();

        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(call.engine.status, CallEngineStatus.failed);
        expect(
          call.sfu.requests.where((r) => r.path == '/sessions/new'),
          hasLength(4),
        );
      });
    });

    test('a pull refused because we were removed ends the call as removed, '
        'with no rejoin and nothing reported', () {
      inCall((call) {
        call.joinEncrypted();
        call.mediaFlows();
        call.sfu.removedFromCall = true;
        call.remoteJoins();

        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(call.engine.status, CallEngineStatus.removed);
        expect(
          call.sfu.requests.where((r) => r.path == '/sessions/new'),
          hasLength(1),
        );
        expect(caught(), isEmpty);
      });
    });

    test('a rejoin refused because we were removed ends the call as removed '
        'at once, rather than retrying', () {
      inCall((call) {
        call.joinEncrypted();
        call.mediaFlows();
        call.sfu.removedFromCall = true;
        call.pc.onConnectionState?.call(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );

        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(call.engine.status, CallEngineStatus.removed);
        expect(
          call.sfu.requests.where((r) => r.path == '/sessions/new'),
          hasLength(2),
        );
        expect(caught(), isEmpty);
      });
    });

    test('a connection that recovers after the removal never revives the '
        'call', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu.removedFromCall = true;
        call.remoteJoins();
        for (final state in [
          RTCPeerConnectionState.RTCPeerConnectionStateClosed,
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        ]) {
          call.pc.changeState(state);
        }
        call.flush();

        expect(call.engine.status, CallEngineStatus.removed);
      });
    });

    test('someone the server removed is refused per track, which is '
        'expected and never reported', () {
      inCall((call) {
        call.joinEncrypted();
        call.mediaFlows();
        call.sfu
          ..missingTracks.addAll(['audio', 'video'])
          ..missingTrackCode = 'IM.ZUNO.CALL_REMOVED';
        call.remoteJoins();

        expect(call.engine.status, isNot(CallEngineStatus.removed));
        expect(caught(), isEmpty);
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

        expect(call.placeholders.created, hasLength(1));
        expect(call.placeholders.released, call.placeholders.created);

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
        call.placeholders.available = false;
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

        call.pc.changeState(
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

        call.pc.changeState(
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

    test('a new connection that fails while the rejoin is still pulling is '
        'replaced too, rather than left silent', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        final gate = Completer<void>();
        call.sfu.pullGate = gate;
        call.async.elapse(const Duration(seconds: 2));
        call.flush();
        expect(call.sfu.pulls.last.path, '/sessions/s2/tracks/new');

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.sfu.pullGate = null;
        gate.complete();
        call.async.elapse(const Duration(seconds: 3));
        call.flush();

        expect(call.sfu.pulls.last.path, '/sessions/s3/tracks/new');
        expect(call.engine.status, isNot(CallEngineStatus.failed));
      });
    });

    test('a publish refused at join rejoins on a new session rather than '
        'failing the call', () {
      inCall((call) {
        call.sfu.refusedPushes = 1;
        call.joinEncrypted();
        expect(call.engine.status, CallEngineStatus.reconnecting);

        call.async.elapse(const Duration(seconds: 2));
        call.flush();

        expect(call.sfu.pushes.map((p) => p.path), [
          '/sessions/s1/tracks/new',
          '/sessions/s2/tracks/new',
        ]);
        expect(call.engine.localFociInfo?['sessionId'], 's2');
        expect(caught(), [startsWith('zuno/caught: publish local tracks:')]);
      });
    });

    test('a rejoin puts the same black placeholder on the new connection', () {
      inCall((call) {
        call.joinEncrypted();

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(
          call.videoSlot.sender.track,
          call.placeholders.created.single.track,
        );
        expect(call.placeholders.released, isEmpty);
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

        call.pc.changeState(
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
    List<StatsReport> uploadLoss(int sent, double fractionLost) => [
      outboundRtp('out-audio', packetsSent: sent),
      remoteInboundRtp('out-audio', fractionLost),
    ];

    test('incoming loss on anyone\'s streams never rates our connection', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins(id: ann, sessionId: 'remote-1');
        call.remoteJoins(id: bob, sessionId: 'remote-2');
        List<StatsReport> poll(int annLost, int bobLost, int received) => [
          inboundRtp('in-ann', lost: annLost, received: received),
          inboundRtp('in-bob', lost: bobLost, received: received),
        ];
        final changesBefore = call.localStateChanges;

        call.pollStats([
          poll(0, 0, 1000),
          poll(300, 0, 1700),
          poll(600, 0, 2400),
          poll(700, 100, 3300),
          poll(800, 200, 4200),
        ]);

        expect(call.engine.quality, CallQuality.good);
        expect(call.localStateChanges, changesBefore);
      }, kind: CallKind.video);
    });

    test('a round trip over 700 ms on our own link rates it poor', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        final changesBefore = call.localStateChanges;

        call.pollStats(polls(3, [roundTrip(0.9)]));

        expect(call.engine.quality, CallQuality.poor);
        expect(call.localStateChanges, greaterThan(changesBefore));
        expect(
          call.engine.localFociInfo?.containsKey('weakConnection'),
          isFalse,
        );
      }, kind: CallKind.video);
    });

    test('a peer\'s old weak-link flags in its membership are not read', () {
      inCall((call) {
        call.joinEncrypted();

        call.engine.updateRemoteParticipant(ann, {
          'sessionId': 'remote-1',
          'tracks': {'audio': 'audio'},
          'encrypted': true,
          'weakConnection': true,
          'lowBandwidth': true,
        }, membershipEventId: r'$membership');
        call.flush();

        expect(call.remote()?.weakConnection, isFalse);
      });
    });

    test('loss Cloudflare reports on our upload still rates it', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        call.pollStats([
          uploadLoss(1000, 0.2),
          uploadLoss(1150, 0.2),
          uploadLoss(1300, 0.2),
        ]);

        expect(call.engine.quality, CallQuality.poor);
      }, kind: CallKind.video);
    });

    test('with the camera off, loss and round trip still count', () {
      inCall((call) {
        call.joinEncrypted();

        call.pollStats(polls(3, [roundTrip(0.5)]));

        expect(call.engine.quality, CallQuality.degraded);
      });
    });

    test('a single bad sample changes nothing', () {
      inCall((call) {
        call.joinEncrypted();
        final applied = call.videoSlot.sender.appliedParameters.length;

        call.pollStats(polls(2, [roundTrip(0.9)]));

        expect(call.videoSlot.sender.appliedParameters, hasLength(applied));
        expect(call.engine.quality, CallQuality.good);
      }, kind: CallKind.video);
    });

    List<List<StatsReport>> cameraHeldTo(double uploadBps) => polls(3, [
      outboundRtp('out-video', kind: 'video'),
      candidatePair('pair', uploadBps: uploadBps),
    ]);

    test('a starved upload rates our link degraded', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        call.pollStats(cameraHeldTo(180000));

        expect(call.engine.quality, CallQuality.degraded);
      }, kind: CallKind.video);
    });

    test('in a voice call a low video target is not taken for a weak '
        'upload', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        call.pollStats(cameraHeldTo(50000));

        expect(call.engine.quality, CallQuality.good);
      });
    });

    test('a peer that rates its link poor shows as weak and never lowers our '
        'video', () {
      inCall((call) {
        call.sfu.connectOnPush = true;
        call.joinEncrypted();
        call.pollStats([[]]);
        call.remoteJoins(advertisesQuality: true);
        final applied = call.videoSlot.sender.appliedParameters.length;

        call.pc.dataChannels.last.receive('{"quality":"poor"}');
        call.flush();

        expect(call.remote()?.weakConnection, isTrue);
        expect(call.videoSlot.sender.appliedParameters, hasLength(applied));
        expect(layer(call.videoSlot.sender, 'h').maxBitrate, 950000);
      }, kind: CallKind.video);
    });
  });

  group('simulcast', () {
    List<(String?, double?, int?, int?)> described(
      List<RTCRtpEncoding> encodings,
    ) => [
      for (final e in encodings)
        (e.rid, e.scaleResolutionDownBy, e.maxFramerate, e.maxBitrate),
    ];

    final layers = described(simulcastEncodingsFor(lowDataMode: false));

    test('the video sender is created with both layers', () {
      inCall((call) {
        call.join();

        expect(described(call.videoSlot.sendEncodings!), layers);
        expect(
          described(call.videoSlot.sender.appliedParameters.last.encodings!),
          layers,
        );
      }, kind: CallKind.video);
    });

    test('a camera swap writes both layers again', () {
      inCall((call) {
        call.joinEncrypted();
        final applied = call.videoSlot.sender.appliedParameters.length;

        call.wait(call.engine.setCameraEnabled(false));
        call.wait(call.engine.setCameraEnabled(true));

        expect(
          call.videoSlot.sender.appliedParameters.length,
          greaterThan(applied),
        );
        expect(
          described(call.videoSlot.sender.appliedParameters.last.encodings!),
          layers,
        );
      }, kind: CallKind.video);
    });

    test('a voice call\'s placeholder gets both layers without error', () {
      inCall((call) {
        call.join();

        expect(call.videoSlot.sender.track, isNotNull);
        expect(
          [for (final e in call.videoSlot.sendEncodings!) e.rid],
          ['q', 'h'],
        );
        expect(caught(), isEmpty);
      });
    });

    test('video and audio pulls carry no simulcast object', () {
      inCall((call) {
        call.joinEncrypted();

        call.remoteJoins();

        expect(call.sfu.pulls.single.tracks, isNotEmpty);
        expect(
          call.sfu.pulls.single.tracks.where((t) => t.containsKey('simulcast')),
          isEmpty,
        );
      }, kind: CallKind.video);
    });
  });

  group('quality channel', () {
    void joinConnected(EngineHarness call) {
      call.sfu.connectOnPush = true;
      call.joinEncrypted();
      call.pollStats([[]]);
    }

    Iterable<SfuRequest> subscriptions(EngineHarness call) => call
        .sfu
        .channelOpens
        .where((r) => r.dataChannels.any((c) => c['location'] == 'remote'));

    test('the quality channel opens at the first stats poll once the '
        'connection is up, and is advertised', () {
      inCall((call) {
        call.joinEncrypted();
        call.pollStats([[]]);
        expect(call.sfu.establishes, isEmpty);
        expect(call.engine.localFociInfo?.containsKey('dataChannels'), isFalse);

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        call.flush();
        expect(call.sfu.establishes, isEmpty);

        call.pollStats([[]]);

        expect(call.sfu.establishes.single.body, {
          'dataChannel': {
            'location': 'remote',
            'dataChannelName': 'server-events',
          },
        });
        expect(
          call.sfu.renegotiations.last.sessionDescription?['type'],
          'answer',
        );
        expect(call.sfu.channelOpens.single.dataChannels, [
          {'location': 'local', 'dataChannelName': 'quality'},
        ]);
        final channel = call.pc.dataChannel('quality')!;
        expect(channel.negotiated, isTrue);
        expect(channel.id, 1);
        expect(call.engine.localFociInfo?['dataChannels'], {
          'quality': 'quality',
        });
      }, kind: CallKind.video);
    });

    test('the connection coming back up opens no second channel', () {
      inCall((call) {
        joinConnected(call);

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        );
        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        call.flush();

        expect(call.sfu.establishes, hasLength(1));
      }, kind: CallKind.video);
    });

    test('every stats poll sends our rating, though flutter_webrtc never '
        'reports the negotiated channel open', () {
      inCall((call) {
        joinConnected(call);
        final channel = call.pc.dataChannel('quality')!;
        expect(channel.state, isNull);

        call.pollStats(polls(3, [roundTrip(0.5)]));

        expect(channel.sent, [
          '{"quality":"good"}',
          '{"quality":"degraded"}',
          '{"quality":"degraded"}',
        ]);
      }, kind: CallKind.video);
    });

    test('a rejoin opens the channel again on the new session', () {
      inCall((call) {
        joinConnected(call);

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();
        call.pollStats([[]]);

        expect(call.backend.peerConnections, hasLength(2));
        expect([for (final r in call.sfu.establishes) r.session], ['s1', 's2']);
        expect(call.pc.dataChannel('quality'), isNotNull);
        expect(call.engine.localFociInfo?['dataChannels'], {
          'quality': 'quality',
        });
      }, kind: CallKind.video);
    });

    test('a channel setup that fails after Cloudflare\'s offer replaces the '
        'session once and is not tried again in this call', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu
          ..renegotiateStatus = 500
          ..connectOnPush = true;
        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        call.pollStats([[]]);

        call.sfu.renegotiateStatus = null;
        call.pollStats([[]]);

        expect(call.backend.peerConnections, hasLength(2));
        expect(call.sfu.establishes, hasLength(1));
        expect(call.engine.status, CallEngineStatus.connected);
        expect(call.engine.localFociInfo?.containsKey('dataChannels'), isFalse);
        expect(
          caught().where((line) => line.contains('quality channel')),
          hasLength(1),
        );
      }, kind: CallKind.video);
    });

    test('a peer\'s reported rating drives its badge', () {
      inCall((call) {
        joinConnected(call);

        call.remoteJoins(advertisesQuality: true);

        expect(subscriptions(call).single.dataChannels, [
          {
            'location': 'remote',
            'sessionId': 'remote-1',
            'dataChannelName': 'quality',
          },
        ]);
        final subscription = call.pc.dataChannels.last;
        expect(subscription.negotiated, isTrue);
        expect(subscription.id, 2);
        expect(call.remote()?.weakConnection, isFalse);

        subscription.receive('{"quality":"good"}');
        call.flush();
        expect(call.remote()?.weakConnection, isFalse);

        subscription.receive('{"quality":"poor"}');
        call.flush();
        expect(call.remote()?.weakConnection, isTrue);
      }, kind: CallKind.video);
    });

    test('never subscribes to a peer that does not advertise the channel', () {
      inCall((call) {
        joinConnected(call);

        call.remoteJoins();

        expect(subscriptions(call), isEmpty);
        expect(call.remote()?.weakConnection, isFalse);
      }, kind: CallKind.video);
    });

    test('a peer that replaces its session or leaves takes its rating with '
        'it', () {
      inCall((call) {
        joinConnected(call);
        call.remoteJoins(advertisesQuality: true);
        final first = call.pc.dataChannels.last;
        first.receive('{"quality":"poor"}');
        call.flush();

        call.remoteJoins(sessionId: 'remote-2', advertisesQuality: true);

        expect(first.closed, isTrue);
        expect(call.sfu.channelCloses.single.dataChannels, [
          {'id': 2},
        ]);
        expect(call.remote()?.weakConnection, isFalse);
        expect(
          subscriptions(call).last.dataChannels.single['sessionId'],
          'remote-2',
        );

        final second = call.pc.dataChannels.last;
        call.engine.removeRemoteParticipant(ann);
        call.flush();

        expect(second.closed, isTrue);
        expect(call.sfu.channelCloses, hasLength(2));
      }, kind: CallKind.video);
    });

    test('a subscription dropped before our own rejoin is never closed on the '
        'new session, where its number may belong to someone else', () {
      inCall((call) {
        joinConnected(call);
        call.remoteJoins(advertisesQuality: true);
        final gate = Completer<void>();
        call.sfu.pullGate = gate;
        call.remoteJoins(sessionId: 'remote-2', advertisesQuality: true);

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 2));
        call.flush();
        gate.complete();
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(call.sfu.channelCloses.where((r) => r.session == 's2'), isEmpty);
      }, kind: CallKind.video);
    });

    test('a subscription Cloudflare grants after the peer left is closed '
        'there', () {
      inCall((call) {
        joinConnected(call);
        final gate = Completer<void>();
        call.sfu.channelGate = gate;
        call.remoteJoins(advertisesQuality: true);

        call.engine.removeRemoteParticipant(ann);
        call.flush();
        gate.complete();
        call.flush();

        expect(call.sfu.channelCloses.single.dataChannels, [
          {'id': 2},
        ]);
        expect(
          call.pc.dataChannels.where((c) => c.id == 2 && !c.closed),
          isEmpty,
        );
      }, kind: CallKind.video);
    });

    test('a refused subscription is asked for and reported once per peer '
        'session', () {
      inCall((call) {
        joinConnected(call);
        call.sfu.refusedChannelSessions.add('remote-1');

        call.remoteJoins(advertisesQuality: true);
        call.remoteJoins(advertisesQuality: true);
        call.remoteJoins(advertisesQuality: true);

        expect(subscriptions(call), hasLength(1));
        expect(
          caught().where((line) => line.contains('subscribe to call quality')),
          hasLength(1),
        );

        call.remoteJoins(sessionId: 'remote-2', advertisesQuality: true);

        expect(subscriptions(call), hasLength(2));
      }, kind: CallKind.video);
    });

    test('a peer that advertises before our channel opens is subscribed once '
        'it does', () {
      inCall((call) {
        call.remoteJoins(advertisesQuality: true);

        joinConnected(call);

        expect(subscriptions(call), hasLength(1));
      }, kind: CallKind.video);
    });

    test('a module without data-channel routes leaves the call working and '
        'reports once', () {
      inCall((call) {
        call.sfu.refuseDataChannels = true;
        joinConnected(call);
        call.remoteJoins(advertisesQuality: true);

        call.pollStats(polls(3, [roundTrip(0.9)]));

        expect(call.engine.status, CallEngineStatus.connected);
        expect(call.backend.peerConnections, hasLength(1));
        expect(call.engine.localFociInfo?.containsKey('dataChannels'), isFalse);
        expect(call.remote()?.weakConnection, isFalse);
        expect(
          caught().where((line) => line.contains('quality channel')),
          hasLength(1),
        );
      }, kind: CallKind.video);
    });
  });

  group('leaving', () {
    test('leaving releases every decryptor, every key, the capture and the '
        'connection', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();

        call.leave();

        expect(call.backend.cryptors.live, isEmpty);
        expect(call.backend.cryptors.keyProviders, hasLength(3));
        expect(
          call.backend.cryptors.keyProviders,
          everyElement(predicate<FakeKeyProvider>((p) => p.disposed)),
        );
        expect(
          call.backend.streams.where((s) => s.id.startsWith('local_')),
          everyElement(predicate<FakeMediaStream>((s) => s.disposed)),
        );
        expect(call.pc.disposed, isTrue);
        expect(call.engine.status, CallEngineStatus.disconnected);
        expect(call.engine.participants.where((p) => !p.isLocal), isEmpty);
        expect(call.engine.localFociInfo, isNull);
      }, kind: CallKind.video);
    });

    test('hanging up never shows anyone as no longer sending media', () {
      inCall((call) {
        call.sfu.connectOnPush = true;
        call.joinEncrypted();
        call.pollStats([[]]);
        call.remoteJoins(advertisesQuality: true);
        call.pc.dataChannels.last.receive('{"quality":"poor"}');
        call.flush();
        final from = call.emitted.length;

        call.leave();

        expect([
          for (final participants in call.emitted.skip(from))
            for (final p in participants)
              if (!p.isLocal && !p.sendingMedia) p,
        ], isEmpty);
      }, kind: CallKind.video);
    });

    test('leaving a voice call releases the black placeholder', () {
      inCall((call) {
        call.joinEncrypted();

        call.leave();

        expect(call.placeholders.created, hasLength(1));
        expect(call.placeholders.released, call.placeholders.created);
        expect(call.pc.disposed, isTrue);
      });
    });
  });

  group('leaving while a track close is under way', () {
    test('a close that leaving cuts off is not reported as a failure', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        call.sfu.closeGate = Completer<void>();
        call.engine.removeRemoteParticipant(ann);
        call.flush();
        expect(call.sfu.closes, hasLength(1));

        call.leave();
        call.sfu.closeGate!.completeError(
          http.ClientException('Connection closed while receiving data'),
        );
        call.flush();

        expect(logs.where((line) => line.contains('closing tracks')), isEmpty);
      });
    });

    test('no close is sent once leaving has begun', () {
      inCall((call) {
        call.joinEncrypted();
        call.remoteJoins();
        final gate = Completer<void>();
        call.sfu.pullGate = gate;
        call.remoteJoins(id: bob);
        call.engine.removeRemoteParticipant(ann);
        call.flush();

        call.leave();
        gate.complete();
        call.flush();

        expect(call.sfu.closes, isEmpty);
      });
    });
  });

  group('failures on a connection that is gone', () {
    void connectionFails(EngineHarness call) {
      call.pc.changeState(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
      call.async.elapse(const Duration(seconds: 2));
      call.flush();
    }

    test('a receiver that cannot be encrypted on the live connection is '
        'reported', () {
      inCall((call) {
        call.joinEncrypted();
        call.backend.cryptors.failEnableFor.add(
          receiverLabel(ann, MediaKind.audio),
        );

        call.remoteJoins();

        expect(caught(), contains(startsWith('zuno/caught: wrap receiver:')));
      });
    });

    test('a stream whose receiver could not be encrypted never shows', () {
      inCall((call) {
        call.joinEncrypted();
        call.backend.cryptors.failEnableFor.add(
          receiverLabel(ann, MediaKind.video),
        );
        call.remoteJoins();

        call.pc.emitTrack(
          call.pulledMids('video').single,
          FakeMediaStream('ann-video'),
        );
        call.pc.emitTrack(
          call.pulledMids('audio').single,
          FakeMediaStream('ann-audio'),
        );
        call.flush();

        expect(call.remote()!.videoStream, isNull);
        expect(call.remote()!.audioStream?.id, 'ann-audio');
      });
    });

    test('a receiver whose connection a rejoin closed is not reported', () {
      inCall((call) {
        call.joinEncrypted();
        final gate = Completer<void>();
        call.backend.cryptors.receiverGate = gate;
        call.remoteJoins();

        connectionFails(call);
        gate.complete();
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(caught(), isEmpty);
        expect(
          call.backend.cryptors.liveLabels,
          contains(receiverLabel(ann, MediaKind.audio)),
        );
      });
    });

    test('a pull still out when a rejoin closes its connection is not '
        'reported', () {
      inCall((call) {
        call.joinEncrypted();
        final gate = Completer<void>();
        call.sfu.pullGate = gate;
        call.remoteJoins();

        connectionFails(call);
        call.sfu.pullGate = null;
        gate.completeError(StateError('session closed'));
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        expect(caught(), isEmpty);
        expect(call.sfu.pulls.last.path, '/sessions/s2/tracks/new');
      });
    });

    test('a pull that fails on the live connection is still reported', () {
      inCall((call) {
        call.joinEncrypted();
        final gate = Completer<void>();
        call.sfu.pullGate = gate;
        call.remoteJoins();

        call.sfu.pullGate = null;
        gate.completeError(StateError('session closed'));
        call.flush();

        expect(
          caught(),
          contains(startsWith('zuno/caught: pull remote tracks:')),
        );
      });
    });

    test('a track adopted as its connection closes is not reported', () {
      inCall((call) {
        call.sfu.reuseMids = true;
        call.joinEncrypted();
        call.remoteJoins();
        final gate = Completer<void>();
        call.backend.adoptGate = gate;
        call.remoteJoins(sessionId: 'remote-2');

        connectionFails(call);
        for (final track in ['audio', 'video']) {
          call.backend.adoptErrors['adopted_${ann}_$track'] = StateError(
            'track not found',
          );
        }
        gate.complete();
        call.flush();

        expect(caught(), isEmpty);
      });
    });

    test('a rejoin cut short by leaving is not reported', () {
      inCall((call) {
        call.joinEncrypted();
        final gate = Completer<void>();
        call.sfu.sessionGate = gate;
        connectionFails(call);

        final leaving = call.engine.leave();
        call.flush();
        gate.completeError(StateError('engine gone'));
        call.flush();
        call.wait(leaving);

        expect(caught(), isEmpty);
      });
    });
  });
}
