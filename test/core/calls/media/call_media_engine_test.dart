import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/media/call_media_engine.dart';
import 'package:zuno/core/calls/media/webrtc_backend.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/module/call_provider_discovery.dart';
import 'package:zuno/core/calls/module/calls_module.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_call_connection.dart';
import '../../../helpers/fake_webrtc.dart';
import '../../../helpers/hybrid_fake_async.dart';
import '../../../helpers/platform_capabilities.dart';

class _Core {
  _Core(this.async, {required CallKind kind, required bool gateOpen}) {
    connections = FakeCallConnections(journal: backend.journal)
      ..openGate = gateOpen ? Completer<void>() : null;
    engine = CallMediaEngine(
      connections: connections,
      spec: (roomId: '!room:example.org', callId: 'call1'),
      kind: kind,
      webRtc: backend,
      capabilities: androidCapabilities,
    );
    engine.participantsStream.listen(emitted.add);
  }

  final FakeAsync async;
  final backend = FakeWebRtcBackend();
  late final FakeCallConnections connections;
  late final CallMediaEngine engine;
  final emitted = <List<CallEngineParticipant>>[];

  FakeCallConnection get connection => connections.connection;

  T wait<T>(Future<T> future) => async.waitFor(future);

  void flush() => async.flushAll();

  void join() => wait(engine.join());

  void encrypt() => wait(keyEveryone(engine));

  void leave() => wait(engine.leave());

  void remoteUpdates(
    Map<String, Object?> fociInfo, {
    String? membershipEventId = r'$membership',
  }) {
    engine.updateRemoteParticipant(
      ann,
      fociInfo,
      membershipEventId: membershipEventId,
    );
    flush();
  }

  CallEngineParticipant get local =>
      engine.participants.firstWhere((p) => p.isLocal);

  CallEngineParticipant? get remote =>
      engine.participants.where((p) => p.id == ann).firstOrNull;

  MediaStreamTrack get microphone => local.audioStream!.getAudioTracks().single;
}

void _run(
  void Function(_Core core) body, {
  CallKind kind = CallKind.voice,
  bool gateOpen = false,
}) {
  fakeAsync((async) {
    final core = _Core(async, kind: kind, gateOpen: gateOpen);
    body(core);
    core.leave();
    core.flush();
  });
}

bool _removesEncryption(String entry) =>
    entry.endsWith('cryptor disposed') || entry == 'key provider disposed';

void main() {
  group('joining', () {
    test('a key set before join enables no track until the joined sender is '
        'wrapped', () {
      _run((core) {
        core.encrypt();
        final gate = Completer<void>();
        core.backend.cryptors.senderGate = gate;

        final joining = core.engine.join();
        core.flush();

        final audio = core.connection.senders[MediaKind.audio]!;
        expect(audio.placements, [(track: core.microphone, enabled: false)]);
        expect(core.microphone.enabled, isFalse);

        gate.complete();
        core.wait(joining);

        expect(core.backend.cryptors.liveLabels, {'local-audio'});
        expect(core.microphone.enabled, isTrue);
      });
    });

    test('mute and camera off made before join apply once the connection is '
        'up', () {
      _run((core) {
        core.wait(core.engine.setMicrophoneMuted(true));
        core.wait(core.engine.setCameraEnabled(false));
        core.encrypt();

        core.join();

        expect(core.connection.shownVideo, [null]);
        expect(core.microphone.enabled, isFalse);
        expect(core.local.audioMuted, isTrue);
        expect(core.local.videoEnabled, isFalse);
        expect(core.engine.status, CallEngineStatus.connected);
      }, kind: CallKind.video);
    });

    test('a connection that cannot be opened fails the join', () {
      _run((core) {
        core.connections.openError = StateError('no provider');

        expect(core.join, throwsA(isA<StateError>()));

        expect(core.engine.status, CallEngineStatus.failed);
        expect(core.engine.localFociInfo, isNull);
      });
    });
  });

  group('readiness', () {
    test('ready throws what the open throws', () {
      _run((core) {
        core.connections.openError = const CallsNotOffered();

        expect(core.engine.ready, throwsA(isA<CallsNotOffered>()));
      });
    });

    test('ready waits for the connection to open', () {
      _run((core) {
        var done = false;
        core.engine.ready().then((_) => done = true);
        core.flush();
        expect(done, isFalse);

        core.connections.openGate!.complete();
        core.flush();

        expect(done, isTrue);
        expect(core.connections.opened, hasLength(1));
      }, gateOpen: true);
    });
  });

  group('a stale provider', () {
    test('route gone at join rediscovers once and joins the new '
        'connection', () {
      _run((core) {
        core.connection.joinError = const CallsRouteGone('POST /sessions/new');
        core.remoteUpdates({'encrypted': true});

        core.join();

        expect(core.connections.rediscoveries, [false, true]);
        expect(core.connections.opened, hasLength(2));
        expect(core.connections.opened.first.closed, isTrue);
        final second = core.connections.opened.last;
        expect(second.joins, 1);
        expect(second.remoteUpdates.map((u) => u.id), [ann]);
        expect(core.engine.status, CallEngineStatus.connected);
      });
    });

    test('a remote update during the reopen reaches the fresh connection', () {
      _run((core) {
        core.connection.joinError = const CallsRouteGone('POST /sessions/new');
        core.connections.rediscoverGate = Completer<void>();
        final joining = core.engine.join();
        core.flush();

        core.remoteUpdates({'encrypted': true});
        core.connections.rediscoverGate!.complete();
        core.flush();
        core.wait(joining);

        expect(core.connections.opened.last.remoteUpdates.map((u) => u.id), [
          ann,
        ]);
      });
    });

    test('a second route gone fails without a third open', () {
      _run((core) {
        core.connection.joinError = const CallsRouteGone('POST /sessions/new');
        core.connections.joinErrors.add(
          const CallsRouteGone('POST /sessions/new'),
        );

        expect(core.join, throwsA(isA<CallsRouteGone>()));

        expect(core.connections.opened, hasLength(2));
        expect(core.connections.rediscoveries, [false, true]);
        expect(core.engine.status, CallEngineStatus.failed);
      });
    });

    test('a hang-up while the stale connection closes asks for no provider '
        'and opens nothing', () {
      _run((core) {
        core.connection
          ..joinError = const CallsRouteGone('POST /sessions/new')
          ..closeGate = Completer<void>();
        final stale = core.connection;
        final joining = core.engine.join();
        core.flush();

        core.leave();
        stale.closeGate!.complete();
        core.flush();
        core.wait(joining);

        expect(core.connections.rediscoveries, [false]);
        expect(core.connections.opened, [stale]);
      });
    });

    test('route gone then none fails as CallsNotOffered', () {
      _run((core) {
        core.connection.joinError = const CallsRouteGone('POST /sessions/new');
        core.connections.rediscoverError = const CallsNotOffered();

        expect(core.join, throwsA(isA<CallsNotOffered>()));

        expect(core.connections.opened, hasLength(1));
        expect(core.engine.status, CallEngineStatus.failed);
      });
    });
  });

  group('our membership', () {
    test('localFociInfo merges the shared flags into the connection '
        'handle', () {
      _run((core) {
        core.join();
        core.connection.handle = {
          'sessionId': 's1',
          'tracks': {'audio': 'audio'},
        };

        expect(core.engine.localFociInfo, {
          'sessionId': 's1',
          'tracks': {'audio': 'audio'},
          'audioMuted': false,
          'videoEnabled': false,
          'encrypted': false,
        });
      });
    });

    test('our membership is encrypted only once our send slot holds our '
        'key', () {
      _run((core) {
        core.join();
        core.connection.handle = {'sessionId': 's1'};

        core.wait(core.engine.setOwnKey(1, keyBytes()));
        expect(core.engine.localFociInfo?['encrypted'], isFalse);

        core.wait(core.engine.sendWithSlot(1));
        expect(core.engine.localFociInfo?['encrypted'], isTrue);
        expect(core.local.encrypted, isTrue);
      });
    });

    test('localFociInfo is null while the connection has no handle', () {
      _run((core) {
        expect(core.engine.localFociInfo, isNull);

        core.join();

        expect(core.engine.localFociInfo, isNull);
      });
    });
  });

  group('remote members', () {
    List<Set<MediaKind>> wanted(_Core core) => [
      for (final update in core.connection.remoteUpdates) update.wanted,
    ];

    test('updateRemoteParticipant passes wanted kinds only when both sides '
        'are encrypted', () {
      _run((core) {
        core.join();

        core.remoteUpdates({'encrypted': true});
        core.encrypt();
        core.remoteUpdates({'encrypted': true, 'videoEnabled': true});
        core.remoteUpdates({'encrypted': false, 'videoEnabled': true});

        expect(wanted(core), [
          <MediaKind>{},
          {MediaKind.audio},
          {MediaKind.audio, MediaKind.video},
          <MediaKind>{},
        ]);
      });
    });

    test('a remote\'s media is wanted only once we hold its own key and it '
        'reports encrypted', () {
      _run((core) {
        core.join();
        core.wait(core.engine.setOwnKey(1, keyBytes()));
        core.wait(core.engine.sendWithSlot(1));

        core.remoteUpdates({'encrypted': true});
        core.wait(core.engine.setPeerKey(bob, 1, keyBytes()));
        core.remoteUpdates({'encrypted': true});
        core.wait(core.engine.setPeerKey(ann, 1, keyBytes()));

        expect(wanted(core), [
          <MediaKind>{},
          <MediaKind>{},
          {MediaKind.audio},
        ]);
      });
    });

    test('forgetting a remote stops wanting its media', () {
      _run((core) {
        core.join();
        core.wait(core.engine.setPeerKey(ann, 1, keyBytes()));
        core.remoteUpdates({'encrypted': true});

        core.wait(core.engine.forgetPeer(ann));

        expect(wanted(core).last, <MediaKind>{});
      });
    });

    test('membershipEventId reaches the connection with each remote '
        'update', () {
      _run((core) {
        core.join();

        core.remoteUpdates({'encrypted': true}, membershipEventId: r'$first');
        core.remoteUpdates({'encrypted': true}, membershipEventId: r'$second');
        core.encrypt();

        expect(
          [
            for (final update in core.connection.remoteUpdates)
              update.membershipEventId,
          ],
          [r'$first', r'$second', r'$second'],
        );
      });
    });

    test('a membership that arrives before the connection opens reaches it '
        'once it does', () {
      _run((core) {
        core.remoteUpdates({'encrypted': true});
        expect(core.remote, isNull);

        core.connections.openGate!.complete();
        core.flush();

        expect(core.connection.remoteUpdates.single.fociInfo, {
          'encrypted': true,
        });
      }, gateOpen: true);
    });

    test('a remote shows as encrypted only once we hold its key, whatever its '
        'membership claims', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true, 'videoEnabled': true});
        expect(core.remote?.encrypted, isFalse);
        expect(core.connection.remoteUpdates.last.wanted, isEmpty);

        core.wait(core.engine.setPeerKey(ann, 0, keyBytes()));

        expect(core.remote?.encrypted, isTrue);
        expect(core.connection.remoteUpdates.last.wanted, {
          MediaKind.audio,
          MediaKind.video,
        });
      });
    });

    test('a peer\'s key touches only its receivers, never our senders or our '
        'membership', () {
      _run((core) {
        core.encrypt();
        core.join();
        core.remoteUpdates({'encrypted': true});
        var localChanges = 0;
        core.engine.localStateChangedStream.listen((_) => localChanges++);
        final cryptors = core.backend.cryptors.cryptors.length;

        core.wait(core.engine.setPeerKey(ann, 1, keyBytes()));
        core.flush();

        expect(localChanges, 0);
        expect(core.backend.cryptors.cryptors, hasLength(cryptors));
      });
    });

    test('sendingMedia comes from the connection and remotesChanged '
        'rebuilds participants', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true});
        expect(core.remote?.sendingMedia, isFalse);
        final emissions = core.emitted.length;

        core.connection.sending.add(ann);
        core.connection.host.remotesChanged();
        core.flush();

        expect(core.emitted, hasLength(emissions + 1));
        expect(
          core.emitted.last.singleWhere((p) => p.id == ann).sendingMedia,
          isTrue,
        );
      });
    });

    test('a membership the connection does not match is never a '
        'participant', () {
      _run((core) {
        core.join();
        core.connection.matches = (_) => false;

        core.remoteUpdates({'encrypted': true});

        expect(core.remote, isNull);
        expect(core.connection.remoteUpdates, hasLength(1));
      });
    });

    test('a departed member leaves the connection and the participants', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true});

        core.engine.removeRemoteParticipant(ann);
        core.flush();

        expect(core.connection.removedRemotes, [ann]);
        expect(core.remote, isNull);
      });
    });
  });

  group('remote media', () {
    FakeReceiver annReceiver() =>
        FakeReceiver('ann-audio-receiver', FakeTrack('audio', 'ann-audio'));

    void streamArrives(_Core core) {
      core.connection.host.setRemoteStream(
        ann,
        MediaKind.audio,
        FakeMediaStream('ann-audio'),
      );
      core.flush();
    }

    test('a peer key arriving after its receiver was adopted wraps it with '
        'that peer\'s keys', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true});
        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            annReceiver(),
          ),
        );
        streamArrives(core);
        expect(core.remote?.audioStream, isNull);

        core.wait(core.engine.setPeerKey(ann, 2, keyBytes()));

        expect(core.remote?.audioStream?.id, 'ann-audio');
        final cryptor = core.backend.cryptors.live.single;
        expect((cryptor.keyProvider! as FakeKeyProvider).slots.keys, [2]);
      });
    });

    test('a sender adopted after a slot switch is wrapped on the current '
        'slot', () {
      _run((core) {
        core.wait(core.engine.setOwnKey(1, keyBytes()));
        core.wait(core.engine.setOwnKey(2, keyBytes()));
        core.wait(core.engine.sendWithSlot(2));

        core.join();

        final sender = core.backend.cryptors.live.single;
        expect(sender.participantId, 'local-audio');
        expect(sender.keyIndexAtEnable, 2);
      });
    });

    test('a remote stream shows only once its receiver has a cryptor', () {
      _run((core) {
        core.join();
        core.encrypt();
        core.remoteUpdates({'encrypted': true});

        streamArrives(core);
        expect(core.remote?.audioStream, isNull);

        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            annReceiver(),
          ),
        );

        expect(core.remote?.audioStream?.id, 'ann-audio');
      });
    });

    test('a receiver that could not be wrapped never shows its stream', () {
      _run((core) {
        core.join();
        core.encrypt();
        core.remoteUpdates({'encrypted': true});
        core.backend.cryptors.failEnableFor.add('$ann-audio');

        expect(
          () => core.wait(
            core.connection.host.adoptReceiver(
              ann,
              MediaKind.audio,
              annReceiver(),
            ),
          ),
          throwsStateError,
        );
        streamArrives(core);

        expect(core.remote?.audioStream, isNull);
      });
    });

    test('a remote stream hidden before the key shows once the key lands '
        'and wraps its receiver', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true});
        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            annReceiver(),
          ),
        );
        streamArrives(core);
        expect(core.remote?.audioStream, isNull);

        core.encrypt();

        expect(core.remote?.audioStream?.id, 'ann-audio');
        expect(core.backend.cryptors.liveLabels, contains('$ann-audio'));
      });
    });

    test('a receiver handed again as a new object while the key wraps it '
        'keeps its cryptor and shows its stream', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true});
        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            annReceiver(),
          ),
        );
        streamArrives(core);
        final wrapping = Completer<void>();
        core.backend.cryptors.receiverGate = wrapping;
        final keying = keyEveryone(core.engine);
        core.flush();

        unawaited(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            annReceiver(),
          ),
        );
        core.flush();
        wrapping.complete();
        core.wait(keying);

        expect(core.backend.cryptors.liveLabels, contains('$ann-audio'));
        expect(core.remote?.audioStream?.id, 'ann-audio');
      });
    });

    test('a sender that cannot be encrypted surfaces the error and keeps '
        'its microphone off', () {
      _run((core) {
        core.join();
        core.backend.cryptors.failEnableFor.add('local-audio');

        expect(() => core.encrypt(), throwsStateError);

        expect(
          core.backend.cryptors.liveLabels,
          isNot(contains('local-audio')),
        );
        expect(core.microphone.enabled, isFalse);
      });
    });

    test('a dropped receiver takes its stream away', () {
      _run((core) {
        core.join();
        core.encrypt();
        core.remoteUpdates({'encrypted': true});
        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            annReceiver(),
          ),
        );
        streamArrives(core);
        expect(core.remote?.audioStream, isNotNull);

        core.wait(core.connection.host.dropReceiver(ann, MediaKind.audio));

        expect(core.remote?.audioStream, isNull);
      });
    });
  });

  group('teardown', () {
    test('leave during open closes the connection that arrives late and '
        'closes local media', () {
      _run((core) {
        core.wait(core.engine.startLocalMedia());
        final joining = core.engine.join();
        core.flush();

        core.leave();

        expect(core.backend.captures.single.disposed, isTrue);
        expect(core.local.audioStream, isNull);

        core.connections.openGate!.complete();
        core.flush();
        core.wait(joining);

        expect(core.connection.closed, isTrue);
        expect(core.connection.joins, 0);
        expect(core.engine.status, CallEngineStatus.disconnected);
        expect(core.engine.localFociInfo, isNull);
      }, gateOpen: true);
    });

    test('leave closes the connection before disposing cryptors', () {
      _run((core) {
        core.join();
        core.encrypt();
        final microphone = core.microphone.id;
        final from = core.backend.journal.length;

        core.leave();

        final leaving = core.backend.journal.sublist(from);
        final closed = leaving.indexOf('connection closed');
        expect(closed, isNonNegative);
        expect(leaving.take(closed), contains('$microphone off'));
        expect(leaving.take(closed).where(_removesEncryption), isEmpty);
        expect(
          leaving.skip(closed),
          containsAll([
            'local-audio cryptor disposed',
            'key provider disposed',
          ]),
        );
      });
    });

    test('a replaced connection turns tracks off before the old one closes, '
        'then drops its cryptors and remote streams', () {
      _run((core) {
        core.join();
        core.encrypt();
        core.remoteUpdates({'encrypted': true});
        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            FakeReceiver('ann-receiver', FakeTrack('audio', 'ann-audio')),
          ),
        );
        core.connection.host.setRemoteStream(
          ann,
          MediaKind.audio,
          FakeMediaStream('ann-audio'),
        );
        expect(core.remote?.audioStream, isNotNull);
        final microphone = core.microphone.id;
        final from = core.backend.journal.length;

        core.wait(
          core.connection.host.connectionReplaced(
            () async => core.backend.journal.add('old connection closed'),
          ),
        );

        final replacing = core.backend.journal.sublist(from);
        final closed = replacing.indexOf('old connection closed');
        expect(closed, isNonNegative);
        expect(replacing.take(closed), contains('$microphone off'));
        expect(replacing.take(closed).where(_removesEncryption), isEmpty);
        expect(
          replacing.skip(closed),
          contains('local-audio cryptor disposed'),
        );
        expect(core.backend.cryptors.live, isEmpty);
        expect(core.remote?.audioStream, isNull);
        expect(core.local.encrypted, isTrue);
      });
    });

    test('a key that lands while the old connection closes wraps nothing on '
        'it', () {
      _run((core) {
        core.join();
        core.remoteUpdates({'encrypted': true});
        core.wait(
          core.connection.host.adoptReceiver(
            ann,
            MediaKind.audio,
            FakeReceiver('ann-receiver', FakeTrack('audio', 'ann-audio')),
          ),
        );
        final closing = Completer<void>();
        final replacing = core.connection.host.connectionReplaced(
          () => closing.future,
        );
        core.flush();

        core.encrypt();

        expect(core.backend.cryptors.cryptors, isEmpty);
        expect(core.microphone.enabled, isFalse);

        closing.complete();
        core.wait(replacing);
      });
    });

    test('a replaced connection whose old peer connection fails to close '
        'still drops its cryptors', () {
      _run((core) {
        core.join();
        core.encrypt();

        expect(
          () => core.wait(
            core.connection.host.connectionReplaced(
              () async => throw StateError('dispose failed'),
            ),
          ),
          throwsStateError,
        );

        expect(core.backend.cryptors.live, isEmpty);
        expect(core.microphone.enabled, isFalse);
      });
    });
  });

  group('our own link', () {
    StatsReport transport(String pair) => StatsReport(
      'transport-$pair',
      'transport',
      0,
      {'selectedCandidatePairId': pair},
    );

    void peerConnections(
      _Core core, {
      required List<StatsReport> sending,
      required List<StatsReport> receiving,
    }) => core.connection.openPeerConnections.addAll([
      FakePeerConnection(const {}, name: 'sending')..stats = sending,
      FakePeerConnection(const {}, name: 'receiving')..stats = receiving,
    ]);

    void threePolls(_Core core) {
      core.async.elapse(const Duration(seconds: 9));
      core.flush();
    }

    test('stats read before the peer connections were replaced are dropped, '
        'and a poll after the swap is used', () {
      _run((core) {
        core.encrypt();
        core.join();
        final stale = Completer<void>();
        peerConnections(core, sending: const [], receiving: const []);
        for (final pc in core.connection.openPeerConnections) {
          (pc as FakePeerConnection).statsGate = stale;
        }

        core.async.elapse(const Duration(seconds: 3));
        core.connection.openPeerConnections
          ..clear()
          ..add(FakePeerConnection(const {}, name: 'replacement'));
        stale.complete();
        core.flush();

        expect(core.connection.observedStats, 0);
        expect(core.connection.sentRatings, isEmpty);

        core.async.elapse(const Duration(seconds: 3));
        core.flush();

        expect(core.connection.observedStats, greaterThan(0));
      });
    });

    test('the upload estimate comes only from the peer connection that '
        'sends', () {
      _run((core) {
        core.encrypt();
        core.join();
        peerConnections(
          core,
          sending: [
            outboundRtp('out-video', kind: 'video', packetsSent: 1000),
            transport('up'),
            candidatePair('up', uploadBps: 180000),
          ],
          receiving: [transport('down'), candidatePair('down', uploadBps: 2e6)],
        );

        threePolls(core);

        expect(core.engine.quality, CallQuality.degraded);
      }, kind: CallKind.video);
    });

    test("a receive-only peer connection's idle estimate is not our "
        'upload', () {
      _run((core) {
        core.encrypt();
        core.join();
        peerConnections(
          core,
          sending: [
            outboundRtp('out-video', kind: 'video', packetsSent: 1000),
            transport('up'),
            candidatePair('up', uploadBps: 2e6),
          ],
          receiving: [
            transport('down'),
            candidatePair('down', uploadBps: 200000),
          ],
        );

        threePolls(core);

        expect(core.engine.quality, CallQuality.good);
      }, kind: CallKind.video);
    });

    test('the round trip is the worst of the selected pairs', () {
      _run((core) {
        core.encrypt();
        core.join();
        peerConnections(
          core,
          sending: [
            outboundRtp('out-audio', packetsSent: 1000),
            transport('up'),
            candidatePair('up', rttSeconds: 0.8),
          ],
          receiving: [
            transport('down'),
            candidatePair('down', rttSeconds: 0.04),
          ],
        );

        threePolls(core);

        expect(core.engine.quality, CallQuality.poor);
      });
    });
  });

  group('the video slot', () {
    test('a voice call switched to video shows the camera on a connection '
        'that publishes video only when asked', () {
      _run((core) {
        core.connection.publishesVideoSlot = false;
        core.encrypt();
        core.join();
        core.connection.slot = VideoSlot.ready;
        expect(core.connection.senders, isNot(contains(MediaKind.video)));

        core.wait(core.engine.switchToVideo());

        final camera = core.local.videoStream!.getVideoTracks().single;
        expect(core.connection.shownVideo, [same(camera)]);
        expect(core.connection.senders[MediaKind.video]?.track, same(camera));
        expect(core.backend.cryptors.liveLabels, contains('local-video'));
        expect(camera.enabled, isTrue);
        expect(core.engine.kind, CallKind.video);
      });
    });

    test('a held video slot keeps a camera change for the next publish', () {
      _run((core) {
        core.join();
        core.connection.shownVideo.clear();
        core.connection.slot = VideoSlot.held;

        core.wait(core.engine.setCameraEnabled(false));

        expect(core.connection.shownVideo, isEmpty);
        expect(core.local.videoStream, isNotNull);

        core.connection.slot = null;
        core.wait(
          core.connection.host.publishLocalMedia(core.connection.publish),
        );

        expect(core.connection.shownVideo, [null]);
        expect(core.local.videoStream, isNull);
      }, kind: CallKind.video);
    });

    test('a camera refused when a held switch to video reaches the publish '
        'turns the camera off and is not reported', () {
      final logs = recordDebugPrints();
      _run((core) {
        core.join();
        core.connection.slot = VideoSlot.held;
        core.wait(core.engine.switchToVideo());
        var localChanges = 0;
        core.engine.localStateChangedStream.listen((_) => localChanges++);
        core.backend.captureError = const CameraRefused();

        core.connection.slot = null;
        core.wait(
          core.connection.host.publishLocalMedia(core.connection.publish),
        );

        expect(logs.where((l) => l.startsWith('zuno/caught:')), isEmpty);
        expect(core.local.videoEnabled, isFalse);
        expect(localChanges, greaterThan(0));
      });
    });

    test('a held video slot leaves a camera switch for later', () {
      _run((core) {
        core.join();
        core.connection.shownVideo.clear();
        core.connection.slot = VideoSlot.held;

        core.wait(core.engine.switchToVideo());

        expect(core.connection.shownVideo, isEmpty);
        expect(core.backend.captureConstraints, hasLength(1));
        expect(core.engine.kind, CallKind.video);
      });
    });
  });
}
