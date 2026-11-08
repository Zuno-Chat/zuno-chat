import 'dart:async';
import 'dart:io' show SocketException, WebSocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_models.pbenum.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_rtc.pb.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/module/calls_module.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_webrtc.dart';
import 'livekit_server_harness.dart';

const _attemptCeilings = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

void main() {
  group('resume', () {
    test('signal lost resumes with reconnect and sid, and restarts ICE', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.sends(SignalResponse(refreshToken: 'lk.fresh'));
        call.flush();
        final publisher = call.publisher;
        final subscriber = call.subscriber;

        call.server.socket.serverCloses();
        call.flush();
        expect(call.engine.status, CallEngineStatus.reconnecting);
        expect(call.connection.videoSlot, VideoSlot.held);

        call.elapse(_attemptCeilings[0]);

        final connect = call.server.connects.last;
        expect(connect.url.queryParameters['reconnect'], '1');
        expect(connect.url.queryParameters['sid'], 'PA_me');
        expect(connect.headers, {'Authorization': 'Bearer lk.fresh'});
        expect(call.module.requests, hasLength(1));
        expect(call.backend.peerConnections, [publisher, subscriber]);
        for (final pc in [publisher, subscriber]) {
          expect(pc.configurations.single['iceServers'], [
            {
              'urls': ['turn:lk2.example.org:443'],
              'username': 'u2',
            },
          ]);
        }
        expect(publisher.iceRestarts, 1);
        expect(call.server.sentOf(SignalRequest_Message.offer), hasLength(1));

        call.server.offersSubscriber(id: 2);
        call.flush();
        expect(
          call.server.sentOf(SignalRequest_Message.answer).single.answer.id,
          2,
        );
        expect(call.engine.status, CallEngineStatus.connected);
        expect(call.connection.videoSlot, VideoSlot.ready);
      });
    });

    test('a resume that cannot reach the server tries the resume again, '
        'keeping the peer connections', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        final peerConnections = [call.publisher, call.subscriber];
        call.server.connectErrors.add(const SocketException('down'));

        call.server.socket.serverCloses();
        call.flush();
        call.elapse(_attemptCeilings[0]);
        call.elapse(_attemptCeilings[1]);

        expect(call.server.connects, hasLength(3));
        expect(
          call.server.connects
              .skip(1)
              .map((c) => c.url.queryParameters['reconnect']),
          ['1', '1'],
        );
        expect(call.module.requests, hasLength(1));
        expect(call.backend.peerConnections, peerConnections);
        call.server.offersSubscriber(id: 2);
        call.flush();
        expect(call.engine.status, CallEngineStatus.connected);
      });
    });

    test('a peer connection disconnected for 5 s resumes', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.subscriber.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        );
        call.flush();
        expect(call.engine.status, CallEngineStatus.reconnecting);
        call.elapse(const Duration(seconds: 4));
        expect(call.server.connects, hasLength(1));

        call.elapse(const Duration(seconds: 1) + _attemptCeilings[0]);

        expect(call.server.connects.last.url.queryParameters['reconnect'], '1');
      });
    });

    test('a peer connection that recovers within 5 s does not resume', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.subscriber.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        );
        call.elapse(const Duration(seconds: 3));
        call.subscriber.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        call.elapse(const Duration(seconds: 10));

        expect(call.server.connects, hasLength(1));
        expect(call.engine.status, CallEngineStatus.connected);
      });
    });

    test('a failed peer connection resumes at once', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.publisher.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.elapse(_attemptCeilings[0]);

        expect(call.server.connects.last.url.queryParameters['reconnect'], '1');
      });
    });

    test('a refused publish resumes and publishes again', () {
      runLiveKitCall((call) {
        final lines = recordDebugPrints();
        call.server.holdTrackPublished = true;
        call.startJoin();
        final cid = call.server.addTracks.single.cid;

        call.server.sends(
          SignalResponse(
            requestResponse: RequestResponse(
              reason: RequestResponse_Reason.LIMIT_EXCEEDED,
              addTrack: AddTrackRequest(cid: cid),
            ),
          ),
        );
        call.wait(call.joining!);

        expect(call.engine.status, CallEngineStatus.reconnecting);
        expect(
          lines,
          contains(
            'zuno/caught: publish to LiveKit: LiveKitTrackRefused: '
            'LIMIT_EXCEEDED',
          ),
        );

        call.server.holdTrackPublished = false;
        call.elapse(_attemptCeilings[0]);

        expect(call.server.connects.last.url.queryParameters['reconnect'], '1');
        expect(call.server.addTracks.single.cid, cid);
        expect(
          call.publisher.rtpTransceivers.single.sender.track,
          same(call.microphone),
        );
      });
    });

    test('a camera turned on during a resume reaches peers once it ends', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.socket.serverCloses();
        call.flush();

        call.wait(call.engine.setCameraEnabled(true));
        expect(
          call.server.addTracks.where((a) => a.type == TrackType.VIDEO),
          isEmpty,
        );

        call.elapse(_attemptCeilings[0]);

        final video = call.server.addTracks.single;
        expect(video.type, TrackType.VIDEO);
        expect(video.cid, call.camera.id);
        expect(call.senderOf(call.camera).track, same(call.camera));
        expect(call.engine.localFociInfo!['videoEnabled'], isTrue);
      });
    });
  });

  group('resume state', () {
    test('a subscription sent just before the socket dies is in the SyncState '
        'after the resume, and its media attaches', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant('PA_ann', 'lk-ann', tracks: [remoteTrack('TR_a')]),
        );
        call.join();
        call.encrypt();
        call.connectPeers();
        final mic = call.microphone.id;

        call.remoteJoins(videoEnabled: false);
        expect(call.server.subscriptions.single.trackSids, ['TR_a']);
        call.server.socket.serverCloses();
        call.elapse(_attemptCeilings[0]);

        final resumed = call.server.socket;
        expect(resumed.resuming, isTrue);
        expect(
          resumed.sent.first.whichMessage(),
          SignalRequest_Message.syncState,
        );
        final sync = resumed.sent.first.syncState;
        expect(sync.subscription.subscribe, isTrue);
        expect(sync.subscription.trackSids, ['TR_a']);
        expect(sync.publishTracks.single.cid, mic);
        expect(sync.publishTracks.single.track.sid, 'TR_$mic');

        call.remoteTrackArrives(participantSid: 'PA_ann', trackSid: 'TR_a');
        expect(call.remote()!.audioStream!.id, 'PA_ann|TR_a');
      });
    });

    test('a track no longer wanted during the outage is unsubscribed after '
        'the resume', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant(
            'PA_ann',
            'lk-ann',
            tracks: [
              remoteTrack('TR_a'),
              remoteTrack('TR_v', type: TrackType.VIDEO),
            ],
          ),
        );
        call.join();
        call.encrypt();
        call.remoteJoins();
        call.connectPeers();

        call.server.socket.serverCloses();
        call.flush();
        call.remoteJoins(videoEnabled: false);
        call.elapse(_attemptCeilings[0]);

        final sync = call.server.socket.sent.first.syncState;
        expect(sync.subscription.trackSids, ['TR_a']);
        final unsubscribe = call.server.subscriptions.single;
        expect(unsubscribe.subscribe, isFalse);
        expect(unsubscribe.trackSids, ['TR_v']);
      });
    });

    test('a subscriber restart offer sent with the reconnect response is '
        'answered on the new ICE servers', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.offersSubscriberWithResume = true;
        final configuring = call.publisher.configurationGate =
            Completer<void>();

        call.server.socket.serverCloses();
        call.elapse(_attemptCeilings[0]);
        expect(call.subscriber.operations, isEmpty);

        configuring.complete();
        call.flush();

        expect(call.subscriber.operations, ['configuration', 'remote offer']);
        expect(
          call.server.sentOf(SignalRequest_Message.answer).single.answer.id,
          3,
        );
      });
    });

    test('a resume whose configuration forces relay makes both peer '
        'connections relay-only', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.resumeForceRelay = true;

        call.server.socket.serverCloses();
        call.elapse(_attemptCeilings[0]);

        for (final pc in [call.publisher, call.subscriber]) {
          expect(pc.configurations.single['iceTransportPolicy'], 'relay');
          expect(pc.configurations.single['iceServers'], [
            {
              'urls': ['turn:lk2.example.org:443'],
              'username': 'u2',
            },
          ]);
        }
      });
    });

    test('a hang-up during the resume connect leaves no open socket', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.connectGate = Completer<void>();
        call.server.socket.serverCloses();
        call.elapse(_attemptCeilings[0]);
        expect(call.server.connects.last.url.queryParameters['reconnect'], '1');

        call.leave();
        call.server.connectGate!.complete();
        call.elapse(const Duration(seconds: 30));

        final resumed = call.server.socket;
        expect(resumed.resuming, isTrue);
        expect(resumed.closed, isTrue);
        expect(resumed.sent, isEmpty);
      });
    });

    List<FakePeerConnection> signalLostWhileResumeWaits(LiveKitCall call) {
      call.join();
      call.connectPeers();
      final peerConnections = [call.publisher, call.subscriber];
      call.server.holdAnswers = true;
      call.server.socket.serverCloses();
      call.elapse(_attemptCeilings[0]);
      return peerConnections;
    }

    test('remote candidates during an ICE restart wait for its answer', () {
      runLiveKitCall((call) {
        signalLostWhileResumeWaits(call);
        expect(call.publisher.iceRestarts, 1);

        call.server.trickles('candidate:new', SignalTarget.PUBLISHER);
        call.flush();
        expect(call.publisher.remoteCandidates, isEmpty);

        call.server.releaseAnswers();
        call.flush();
        expect(call.publisher.remoteDescriptions, hasLength(2));
        expect(call.publisher.remoteCandidates.map((c) => c.candidate), [
          'candidate:new',
        ]);
      });
    });

    test('a second signal loss while a resume waits for its answer resumes '
        'again at once, keeping the token and peer connections', () {
      runLiveKitCall((call) {
        final peerConnections = signalLostWhileResumeWaits(call);
        expect(call.server.connects, hasLength(2));
        expect(call.server.sentOf(SignalRequest_Message.offer), hasLength(1));

        call.server.socket.serverCloses();
        call.flush();
        call.elapse(_attemptCeilings[1]);

        expect(call.server.connects, hasLength(3));
        expect(call.server.connects.last.url.queryParameters['reconnect'], '1');
        expect(call.module.requests, hasLength(1));
        expect(call.backend.peerConnections, peerConnections);
        call.server.releaseAnswers();
        call.server.offersSubscriber(id: 2);
        call.flush();
        expect(call.engine.status, CallEngineStatus.connected);
      });
    });

    test('leave RECONNECT while a resume waits for its answer goes to a full '
        'reconnect without waiting out the answer', () {
      runLiveKitCall((call) {
        signalLostWhileResumeWaits(call);
        expect(call.server.connects, hasLength(2));

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.flush();
        call.elapse(_attemptCeilings[1]);

        expect(call.server.connects, hasLength(3));
        expect(
          call.server.connects.last.url.queryParameters.containsKey(
            'reconnect',
          ),
          isFalse,
        );
        expect(call.module.requests, hasLength(2));
        expect(call.backend.peerConnections, hasLength(4));
      });
    });

    test('a resume whose answer never comes goes to a full reconnect once '
        'the answer deadline passes', () {
      runLiveKitCall((call) {
        signalLostWhileResumeWaits(call);
        expect(call.module.requests, hasLength(1));

        call.elapse(const Duration(seconds: 15));
        call.elapse(_attemptCeilings[1]);

        expect(call.module.requests, hasLength(2));
        expect(call.backend.peerConnections, hasLength(4));
      });
    });
  });

  group('publishing refusals', () {
    test('a queued AddTrack the server never confirms goes to a full '
        'reconnect', () {
      runLiveKitCall((call) {
        final lines = recordDebugPrints();
        call.server.holdTrackPublished = true;
        call.startJoin();
        final cid = call.server.addTracks.single.cid;

        call.server.sends(
          SignalResponse(
            requestResponse: RequestResponse(
              reason: RequestResponse_Reason.QUEUED,
              addTrack: AddTrackRequest(cid: cid),
            ),
          ),
        );
        call.wait(call.joining!);

        expect(call.engine.status, CallEngineStatus.reconnecting);
        expect(
          lines,
          contains(
            'zuno/caught: publish to LiveKit: LiveKitTrackRefused: QUEUED',
          ),
        );

        call.server.holdTrackPublished = false;
        call.elapse(_attemptCeilings[0]);

        expect(call.module.requests, hasLength(2));
        expect(call.server.connects, hasLength(2));
        expect(
          call.server.connects.last.url.queryParameters['reconnect'],
          isNull,
        );
      });
    });

    test('a TrackPublished that came after an abandoned wait is used without '
        'a second AddTrack', () {
      runLiveKitCall((call) {
        call.server.holdTrackPublished = true;
        call.startJoin();
        call.server.leaves(LeaveRequest_Action.RESUME);
        call.flush();
        call.server.releaseTrackPublished();
        call.flush();

        call.elapse(_attemptCeilings[0]);

        expect(call.server.socket.resuming, isTrue);
        expect(call.server.addTracks, isEmpty);
        expect(
          call.publisher.rtpTransceivers.single.sender.track,
          same(call.microphone),
        );
      });
    });

    test('a permanent refusal while a resume re-publishes fails the call at '
        'once', () {
      runLiveKitCall((call) {
        call.server.holdTrackPublished = true;
        call.startJoin();
        call.server.leaves(LeaveRequest_Action.RESUME);
        call.elapse(_attemptCeilings[0]);
        final cid = call.server.addTracks.single.cid;

        call.server.sends(
          SignalResponse(
            requestResponse: RequestResponse(
              reason: RequestResponse_Reason.UNSUPPORTED_TYPE,
              addTrack: AddTrackRequest(cid: cid),
            ),
          ),
        );
        call.elapse(const Duration(seconds: 30));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.module.requests, hasLength(1));
      });
    });

    test('a permanently refused publish fails the call at once', () {
      runLiveKitCall((call) {
        call.server.holdTrackPublished = true;
        call.startJoin();
        final cid = call.server.addTracks.single.cid;

        call.server.sends(
          SignalResponse(
            requestResponse: RequestResponse(
              reason: RequestResponse_Reason.NOT_ALLOWED,
              addTrack: AddTrackRequest(cid: cid),
            ),
          ),
        );
        call.wait(call.joining!);
        call.elapse(const Duration(seconds: 30));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.server.connects, hasLength(1));
      });
    });
  });

  group('full reconnect', () {
    test('resume failure falls back to a full reconnect that re-publishes', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant('PA_ann', 'lk-ann', tracks: [remoteTrack('TR_a')]),
        );
        call.join();
        call.encrypt();
        call.remoteJoins(videoEnabled: false);
        call.connectPeers();
        final oldPublisher = call.publisher;
        final oldSubscriber = call.subscriber;
        call.server.resumeRefusal = SignalResponse(
          leave: LeaveRequest(reason: DisconnectReason.STATE_MISMATCH),
        );

        call.server.socket.serverCloses();
        call.elapse(_attemptCeilings[0]);

        expect(call.module.requests, hasLength(2));
        expect(call.backend.peerConnections, hasLength(4));
        expect(oldPublisher.disposed, isTrue);
        expect(oldSubscriber.disposed, isTrue);
        final socket = call.server.socket;
        expect(socket.resuming, isFalse);
        expect(call.server.addTracks.single.cid, call.microphone.id);
        expect(
          call.publisher.rtpTransceivers.single.sender.track,
          same(call.microphone),
        );
        expect(call.server.subscriptions.single.trackSids, ['TR_a']);
        expect(call.microphone.enabled, isTrue);
        expect(
          call.backend.cryptors.live
              .where((c) => c.participantId == 'local-audio')
              .single
              .sender,
          same(call.publisher.rtpTransceivers.single.sender),
        );

        call.connectPeers();
        expect(call.engine.status, CallEngineStatus.connected);
      });
    });

    test('the old socket closing while a full reconnect waits for its token '
        'does not reconnect twice', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        final old = call.server.socket;

        call.module.gate = Completer<void>();
        call.server.leaves(
          LeaveRequest_Action.DISCONNECT,
          reason: DisconnectReason.PARTICIPANT_REMOVED,
        );
        call.flush();
        call.elapse(const Duration(seconds: 1));

        unawaited(old.serverCloses());
        call.flush();
        call.module.gate!.complete();
        call.module.gate = null;
        call.flush();
        call.connectPeers();
        call.elapse(const Duration(seconds: 2));

        expect(call.engine.status, CallEngineStatus.connected);
        expect(call.module.requests, hasLength(2));
      });
    });

    test('key during full reconnect: no track enabled before its new sender '
        'is wrapped', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.module.gate = Completer<void>();

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);
        expect(call.module.requests, hasLength(2));

        call.encrypt();
        expect(call.microphone.enabled, isFalse);
        expect(call.backend.cryptors.cryptors, isEmpty);

        final wrapping = Completer<void>();
        call.backend.cryptors.senderGate = wrapping;
        call.module.gate!.complete();
        call.flush();

        final sender = call.publisher.rtpTransceivers.single.sender;
        expect(sender.placements, [(track: call.microphone, enabled: false)]);
        expect(call.microphone.enabled, isFalse);

        wrapping.complete();
        call.flush();

        expect(call.microphone.enabled, isTrue);
        expect(call.backend.cryptors.live.single.sender, same(sender));
      });
    });

    test('leave RECONNECT forces a full reconnect', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);

        expect(
          call.server.connects.where(
            (c) => c.url.queryParameters.containsKey('reconnect'),
          ),
          isEmpty,
        );
        expect(call.server.connects, hasLength(2));
        expect(call.module.requests, hasLength(2));
        expect(call.backend.peerConnections, hasLength(4));
        expect(call.server.addTracks, hasLength(1));
      });
    });

    test('a removal leave reconnects on a fresh token and goes on when the '
        'token route grants one', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.server.leaves(
          LeaveRequest_Action.DISCONNECT,
          reason: DisconnectReason.PARTICIPANT_REMOVED,
        );
        call.server.socket.serverCloses();
        call.flush();
        expect(call.engine.status, CallEngineStatus.reconnecting);

        call.elapse(_attemptCeilings[0]);

        expect(call.module.requests, hasLength(2));
        expect(call.server.connects, hasLength(2));
        final connect = call.server.connects.last;
        expect(connect.url.queryParameters.containsKey('reconnect'), isFalse);
        expect(connect.headers, {'Authorization': 'Bearer lk-token-2'});
        expect(call.backend.peerConnections, hasLength(4));
        expect(call.server.addTracks, hasLength(1));

        call.connectPeers();
        expect(call.engine.status, CallEngineStatus.connected);
        expect(call.statuses, isNot(contains(CallEngineStatus.removed)));
        expect(call.statuses, isNot(contains(CallEngineStatus.failed)));
      });
    });

    test('leave RESUME resumes', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.server.leaves(LeaveRequest_Action.RESUME);
        call.elapse(_attemptCeilings[0]);

        expect(call.server.connects.last.url.queryParameters['reconnect'], '1');
        expect(call.module.requests, hasLength(1));
      });
    });

    test('a video call re-publishes its camera after a full reconnect', () {
      runLiveKitCall((call) {
        call.join();
        call.encrypt();
        call.connectPeers();

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);

        expect(call.server.addTracks.map((a) => a.type), [
          TrackType.AUDIO,
          TrackType.VIDEO,
        ]);
        expect(call.senderOf(call.camera).track, same(call.camera));
        expect(call.camera.enabled, isTrue);
        expect(call.connection.videoSlot, VideoSlot.ready);
      }, kind: CallKind.video);
    });
  });

  group('ending', () {
    test('leave DISCONNECT fails the call', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        call.server.leaves(
          LeaveRequest_Action.DISCONNECT,
          reason: DisconnectReason.ROOM_DELETED,
        );
        call.flush();
        call.elapse(const Duration(seconds: 10));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.server.connects, hasLength(1));
      });
    });

    test('a removal leave reports removed once the token route refuses the '
        'fresh token as removed', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.module.answers.add(
          FakeLiveKitModule.refusal({'errcode': 'IM.ZUNO.CALL_REMOVED'}, 403),
        );

        call.server.leaves(
          LeaveRequest_Action.DISCONNECT,
          reason: DisconnectReason.PARTICIPANT_REMOVED,
        );
        call.server.socket.serverCloses();
        call.flush();
        expect(call.engine.status, CallEngineStatus.reconnecting);

        call.elapse(_attemptCeilings[0]);
        call.elapse(const Duration(seconds: 30));

        expect(call.engine.status, CallEngineStatus.removed);
        expect(call.module.requests, hasLength(2));
        expect(call.server.connects, hasLength(1));
        expect(call.statuses, isNot(contains(CallEngineStatus.failed)));
      });
    });

    test('three failed attempts end as failed', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.connectError = const SocketException('down');

        call.server.socket.serverCloses();
        call.flush();
        expect(call.engine.status, CallEngineStatus.reconnecting);
        for (final ceiling in _attemptCeilings) {
          call.elapse(ceiling);
        }

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.server.connects, hasLength(4));
        call.elapse(const Duration(seconds: 30));
        expect(call.server.connects, hasLength(4));
      });
    });

    test('a refused join during a full reconnect fails at once', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.connectErrors.addAll([
          const SocketException('down'),
          const WebSocketException('not upgraded', 401),
        ]);

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.flush();
        call.elapse(_attemptCeilings[0]);
        call.elapse(_attemptCeilings[1]);

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.server.connects, hasLength(3));
        call.elapse(const Duration(seconds: 30));
        expect(call.server.connects, hasLength(3));
      });
    });

    test('a 503 at the upgrade during a full reconnect is tried again', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.server.connectErrors.add(
          const WebSocketException('not upgraded', 503),
        );

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);
        call.elapse(_attemptCeilings[1]);

        expect(call.server.connects, hasLength(3));
        expect(call.backend.peerConnections, hasLength(4));
        call.connectPeers();
        expect(call.engine.status, CallEngineStatus.connected);
      });
    });

    test('a module network failure during a full reconnect retries', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.module.answers.addAll([
          for (var i = 0; i < 3; i++) const SocketException('down'),
        ]);

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);
        expect(call.engine.status, CallEngineStatus.reconnecting);
        call.elapse(const Duration(milliseconds: 500) + _attemptCeilings[1]);

        expect(call.module.requests, hasLength(5));
        expect(call.backend.peerConnections, hasLength(4));
        call.connectPeers();
        expect(call.engine.status, CallEngineStatus.connected);
      });
    });

    test('a full call at token mint during a full reconnect fails at once', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.module.answers.add(
          FakeLiveKitModule.refusal({
            'errcode': 'IM.ZUNO.CALL_FULL',
            'max_participants': 6,
          }, 403),
        );

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);
        call.elapse(const Duration(seconds: 30));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.module.requests, hasLength(2));
      });
    });

    test('a gone token route during a full reconnect fails at once', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.module.answers.add(
          FakeLiveKitModule.refusal({'errcode': 'M_UNRECOGNIZED'}, 404),
        );

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);
        call.elapse(const Duration(seconds: 30));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.module.requests, hasLength(2));
      });
    });

    test('a hang-up while a full reconnect waits for its grant opens '
        'nothing', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        final first = [call.publisher, call.subscriber];
        call.module.gate = Completer<void>();
        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);

        call.leave();
        call.module.gate!.complete();
        call.elapse(const Duration(seconds: 30));

        expect(call.server.connects, hasLength(1));
        expect(call.backend.peerConnections, first);
        expect(first.every((pc) => pc.disposed), isTrue);
      });
    });

    test('a removal at token mint during a full reconnect reports removed', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();
        call.module.answers.add(
          FakeLiveKitModule.refusal({'errcode': 'IM.ZUNO.CALL_REMOVED'}, 403),
        );

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(_attemptCeilings[0]);
        call.elapse(const Duration(seconds: 30));

        expect(call.engine.status, CallEngineStatus.removed);
        expect(call.module.requests, hasLength(2));
        expect(call.statuses, isNot(contains(CallEngineStatus.failed)));
      });
    });

    test('the attempt budget resets after a reconnect that ends connected', () {
      runLiveKitCall((call) {
        call.join();
        call.connectPeers();

        for (var i = 0; i < 4; i++) {
          call.server.leaves(LeaveRequest_Action.RECONNECT);
          call.elapse(_attemptCeilings[0]);
          call.connectPeers();
          expect(call.engine.status, CallEngineStatus.connected);
        }

        expect(call.backend.peerConnections, hasLength(10));
      });
    });

    test('a full call at the first token mint ends as CallFullException', () {
      runLiveKitCall((call) {
        call.module.answers.add(
          FakeLiveKitModule.refusal({
            'errcode': 'IM.ZUNO.CALL_FULL',
            'max_participants': 6,
          }, 403),
        );

        expect(call.join, throwsA(isA<CallFullException>()));

        expect(call.engine.status, CallEngineStatus.failed);
        expect(call.server.connects, isEmpty);
      });
    });

    test('a removal at the first token mint reports removed', () {
      runLiveKitCall((call) {
        call.module.answers.add(
          FakeLiveKitModule.refusal({'errcode': 'IM.ZUNO.CALL_REMOVED'}, 403),
        );

        expect(call.join, throwsA(anything));

        expect(call.engine.status, CallEngineStatus.removed);
        expect(call.server.connects, isEmpty);
      });
    });
  });
}
