import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_models.pb.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_rtc.pb.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/media/call_media_engine.dart';
import 'package:zuno/core/calls/media/call_quality_policy.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_webrtc.dart';
import 'livekit_server_harness.dart';

String _audioAnswer() => [
  'v=0',
  'o=- 1 2 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111',
  'a=rtpmap:111 opus/48000/2',
  'a=fmtp:111 minptime=10;useinbandfec=1',
  '',
].join('\r\n');

String _videoAnswer() => [
  'v=0',
  'o=- 1 2 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111',
  'a=rtpmap:111 opus/48000/2',
  'm=video 9 UDP/TLS/RTP/SAVPF 96 98',
  'a=recvonly',
  'a=rtpmap:96 H264/90000',
  'a=rtpmap:98 VP8/90000',
  '',
].join('\r\n');

void main() {
  group('joining', () {
    test('join publishes audio with GCM and disable_red, and offers only '
        'after TrackPublished', () {
      runLiveKitCall((call) {
        call.server.holdTrackPublished = true;
        call.startJoin();

        final add = call.server.addTracks.single;
        expect(add.cid, call.microphone.id);
        expect(add.type, TrackType.AUDIO);
        expect(add.source, TrackSource.MICROPHONE);
        expect(add.encryption, Encryption_Type.GCM);
        expect(add.disableRed, isTrue);
        expect(add.muted, isFalse);
        expect(call.publisher.rtpTransceivers, isEmpty);
        expect(call.server.sentOf(SignalRequest_Message.offer), isEmpty);

        call.server.releaseTrackPublished();
        call.wait(call.joining!);

        final transceiver = call.publisher.rtpTransceivers.single;
        expect(transceiver.direction, TransceiverDirection.SendOnly);
        expect(transceiver.sender.track, same(call.microphone));
        expect(call.server.sentOf(SignalRequest_Message.offer), hasLength(1));
        expect(call.publisher.offerConstraints.single, isEmpty);
        expect(call.publisher.remoteDescriptions.single.type, 'answer');
      });
    });

    test(
      'a voice call publishes video only on the first showVideo(camera)',
      () {
        runLiveKitCall((call) {
          call.join();
          expect(call.server.addTracks, hasLength(1));
          expect(call.connection.videoSlot, VideoSlot.ready);

          call.wait(call.engine.setCameraEnabled(true));

          final adds = call.server.addTracks;
          expect(adds, hasLength(2));
          final video = adds.last;
          expect(video.cid, call.camera.id);
          expect(video.type, TrackType.VIDEO);
          expect(video.source, TrackSource.CAMERA);
          expect(video.encryption, Encryption_Type.GCM);
          expect(video.disableRed, isTrue);
          expect(video.layers.map((l) => l.quality), [
            VideoQuality.LOW,
            VideoQuality.HIGH,
          ]);
          expect(video.layers.map((l) => l.bitrate), [200000, 950000]);
          expect(video.simulcastCodecs, hasLength(1));
          final declared = video.simulcastCodecs.single;
          expect(declared.codec, 'vp8');
          expect(declared.cid, call.camera.id);
          expect(declared.layers.map((l) => l.quality), [
            VideoQuality.LOW,
            VideoQuality.HIGH,
          ]);
          final transceiver = call.publisher.rtpTransceivers.last;
          expect(transceiver.sender.track, same(call.camera));
          expect(transceiver.direction, TransceiverDirection.SendOnly);
          expect(transceiver.sendEncodings!.map((e) => e.rid), ['q', 'h']);
          expect(call.server.sentOf(SignalRequest_Message.offer), hasLength(2));
          expect(call.engine.kind, CallKind.video);
          expect(call.engine.localFociInfo!['videoEnabled'], isTrue);
        });
      },
    );

    test('a video call publishes its camera at join', () {
      runLiveKitCall((call) {
        call.join();

        expect(call.server.addTracks.map((a) => a.type), [
          TrackType.AUDIO,
          TrackType.VIDEO,
        ]);
        expect(call.server.sentOf(SignalRequest_Message.offer), hasLength(1));
        expect(call.senderOf(call.camera).track, same(call.camera));
      }, kind: CallKind.video);
    });

    test('the publisher answer lists VP8 first and carries the start '
        'bitrate', () {
      runLiveKitCall((call) {
        call.server.answerSdp = _videoAnswer();

        call.join();

        final answer = call.publisher.remoteDescriptions.single.sdp!;
        expect(answer, contains('m=video 9 UDP/TLS/RTP/SAVPF 98 96\r\n'));
        expect(
          answer,
          contains(
            'a=rtpmap:98 VP8/90000\r\n'
            'a=fmtp:98 x-google-start-bitrate=$startBitrateKbps\r\n',
          ),
        );
        expect(answer, isNot(contains('usedtx')));
      }, kind: CallKind.video);
    });

    test('audio is published without Opus DTX, so the server answer never '
        'turns it on', () {
      runLiveKitCall((call) {
        call.server.answerSdp = _audioAnswer();

        call.join();

        final answer = call.publisher.remoteDescriptions.single.sdp!;
        expect(answer, contains('a=fmtp:111 minptime=10;useinbandfec=1\r\n'));
        expect(answer, isNot(contains('usedtx')));
        expect(call.server.addTracks.single.audioFeatures, [
          AudioTrackFeature.TF_NO_DTX,
        ]);
      });
    });

    test('handle carries the identity from the join response', () {
      runLiveKitCall((call) {
        expect(call.engine.localFociInfo, isNull);

        call.join();

        expect(call.engine.localFociInfo, {
          'identity': 'lk-me',
          'audioMuted': false,
          'videoEnabled': false,
          'encrypted': false,
        });
      });
    });

    test('force_relay sets relay-only', () {
      runLiveKitCall((call) {
        call.server.forceRelay = true;

        call.join();

        for (final pc in [call.publisher, call.subscriber]) {
          expect(pc.configuration['iceTransportPolicy'], 'relay');
          expect(pc.configuration['iceServers'], [
            {
              'urls': ['turn:lk.example.org:443?transport=tcp'],
              'username': 'u',
              'credential': 'c',
            },
          ]);
        }
      });
    });

    test('without force_relay every candidate type is allowed', () {
      runLiveKitCall((call) {
        call.join();

        for (final pc in [call.publisher, call.subscriber]) {
          expect(pc.configuration.containsKey('iceTransportPolicy'), isFalse);
        }
      });
    });

    test('status is connecting until both peer connections connect', () {
      runLiveKitCall((call) {
        call.join();
        expect(call.statuses, [CallEngineStatus.connecting]);

        call.publisher.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        call.flush();
        expect(call.engine.status, CallEngineStatus.connecting);

        call.subscriber.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        );
        call.flush();
        expect(call.statuses, [
          CallEngineStatus.connecting,
          CallEngineStatus.connected,
        ]);
      });
    });
  });

  group('negotiation', () {
    test('subscriber offer is answered while a publisher offer is pending', () {
      runLiveKitCall((call) {
        call.server.holdAnswers = true;
        call.startJoin();
        expect(call.server.sentOf(SignalRequest_Message.offer), hasLength(1));
        expect(call.publisher.remoteDescriptions, isEmpty);

        call.server.offersSubscriber(id: 7);
        call.flush();

        final answer = call.server
            .sentOf(SignalRequest_Message.answer)
            .single
            .answer;
        expect(answer.type, 'answer');
        expect(answer.id, 7);
        expect(call.subscriber.remoteDescriptions.single.type, 'offer');
        expect(call.publisher.remoteDescriptions, isEmpty);

        call.server.releaseAnswers();
        call.wait(call.joining!);
        expect(call.publisher.remoteDescriptions, hasLength(1));
      });
    });

    test('a subscriber offer sent with the join response is answered', () {
      runLiveKitCall((call) {
        call.server.offersSubscriberWithJoin = true;

        call.join();

        expect(
          call.server.sentOf(SignalRequest_Message.answer).single.answer.id,
          3,
        );
        expect(call.subscriber.remoteDescriptions.single.type, 'offer');
      });
    });

    test('remote candidates wait for the remote description, and local ones '
        'are trickled with their target', () {
      runLiveKitCall((call) {
        call.join();
        call.server.trickles('candidate:sub', SignalTarget.SUBSCRIBER);
        call.flush();
        expect(call.subscriber.remoteCandidates, isEmpty);

        call.server.offersSubscriber();
        call.flush();
        expect(call.subscriber.remoteCandidates.map((c) => c.candidate), [
          'candidate:sub',
        ]);

        call.server.trickles('candidate:pub', SignalTarget.PUBLISHER);
        call.flush();
        expect(call.publisher.remoteCandidates.map((c) => c.candidate), [
          'candidate:pub',
        ]);

        call.subscriber.onIceCandidate?.call(
          RTCIceCandidate('candidate:mine', '0', 0),
        );
        final trickle = call.server
            .sentOf(SignalRequest_Message.trickle)
            .single
            .trickle;
        expect(trickle.target, SignalTarget.SUBSCRIBER);
        expect(jsonDecode(trickle.candidateInit), {
          'candidate': 'candidate:mine',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        });
      });
    });
  });

  group('receiving', () {
    test('subscribes only to GCM tracks of wanted kinds', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant(
            'PA_ann',
            'lk-ann',
            tracks: [
              remoteTrack('TR_ann_gcm'),
              remoteTrack('TR_ann_none', encryption: Encryption_Type.NONE),
              remoteTrack('TR_ann_video', type: TrackType.VIDEO),
            ],
          ),
        );
        call.join();
        call.remoteJoins(videoEnabled: false);
        expect(call.server.subscriptions, isEmpty);

        call.encrypt();

        final subscription = call.server.subscriptions.single;
        expect(subscription.subscribe, isTrue);
        expect(subscription.trackSids, ['TR_ann_gcm']);
      });
    });

    test('early track waits for ParticipantUpdate and membership, then '
        'attaches to the right device', () {
      runLiveKitCall((call) {
        call.join();
        call.encrypt();
        call.remoteJoins(id: bob, identity: 'lk-bob');

        call.remoteTrackArrives(participantSid: 'PA_ann', trackSid: 'TR_ann_a');
        expect(call.remote(bob)!.audioStream, isNull);

        call.server.participantUpdate([
          remoteParticipant(
            'PA_ann',
            'lk-ann',
            tracks: [remoteTrack('TR_ann_a')],
          ),
          remoteParticipant(
            'PA_bob',
            'lk-bob',
            tracks: [remoteTrack('TR_bob_a')],
          ),
        ]);
        call.flush();
        expect(call.remote(bob)!.audioStream, isNull);
        expect(call.remote(ann), isNull);

        call.remoteJoins();

        expect(call.remote(ann)!.audioStream!.id, 'PA_ann|TR_ann_a');
        expect(call.remote(bob)!.audioStream, isNull);
        expect(
          call.backend.cryptors.liveLabels,
          contains(receiverLabel(ann, MediaKind.audio)),
        );
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(bob, MediaKind.audio))),
        );
        expect(
          call.server.subscriptions.expand((s) => s.trackSids),
          containsAll(['TR_bob_a', 'TR_ann_a']),
        );
      });
    });

    test('an early track attaches only once both sides are encrypted', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant('PA_ann', 'lk-ann', tracks: [remoteTrack('TR_a')]),
        );
        call.join();
        call.encrypt();
        call.remoteJoins(encrypted: false);

        call.remoteTrackArrives(participantSid: 'PA_ann', trackSid: 'TR_a');
        expect(call.remote()!.audioStream, isNull);
        expect(call.server.subscriptions, isEmpty);

        call.remoteJoins();

        expect(call.server.subscriptions.single.trackSids, ['TR_a']);
        expect(call.remote()!.audioStream!.id, 'PA_ann|TR_a');
      });
    });

    test('a track for an identity with no membership is never attached', () {
      runLiveKitCall((call) {
        call.join();
        call.encrypt();
        call.server.participantUpdate([
          remoteParticipant(
            'PA_eve',
            'lk-eve',
            tracks: [remoteTrack('TR_eve')],
          ),
        ]);
        call.remoteTrackArrives(participantSid: 'PA_eve', trackSid: 'TR_eve');

        call.remoteJoins();

        expect(call.server.subscriptions, isEmpty);
        expect(call.remote()!.audioStream, isNull);
        expect(call.backend.cryptors.liveLabels, {'local-audio'});
      });
    });

    test('a track whose receiver could not be encrypted never shows', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant('PA_ann', 'lk-ann', tracks: [remoteTrack('TR_a')]),
        );
        call.join();
        call.encrypt();
        call.remoteJoins();
        call.backend.cryptors.failEnableFor.add(
          receiverLabel(ann, MediaKind.audio),
        );

        call.remoteTrackArrives(participantSid: 'PA_ann', trackSid: 'TR_a');

        expect(call.remote()!.audioStream, isNull);
      });
    });

    test('a track that is removed detaches from its device', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant('PA_ann', 'lk-ann', tracks: [remoteTrack('TR_a')]),
        );
        call.join();
        call.encrypt();
        call.remoteJoins();
        call.remoteTrackArrives(participantSid: 'PA_ann', trackSid: 'TR_a');
        final stream = call.remote()!.audioStream!;

        call.subscriber.onRemoveTrack?.call(stream, FakeTrack('audio', 'r-a'));
        call.flush();

        expect(call.remote()!.audioStream, isNull);
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(ann, MediaKind.audio))),
        );
      });
    });

    test('a receiver reused for another track never shows the earlier '
        "person's track", () {
      runLiveKitCall((call) {
        call.server.others.addAll([
          remoteParticipant(
            'PA_ann',
            'lk-ann',
            tracks: [remoteTrack('TR_av', type: TrackType.VIDEO)],
          ),
          remoteParticipant(
            'PA_bob',
            'lk-bob',
            tracks: [remoteTrack('TR_bv', type: TrackType.VIDEO)],
          ),
        ]);
        call.join();
        call.encrypt();
        call.connectPeers();
        call.remoteJoins();
        call.remoteJoins(id: bob, identity: 'lk-bob', videoEnabled: false);
        call.remoteTrackArrives(
          participantSid: 'PA_ann',
          trackSid: 'TR_av',
          kind: 'video',
        );
        final native = call.subscriber.rtpTransceivers.last.receiver;
        call.remoteJoins(videoEnabled: false);

        call.remoteJoins(id: bob, identity: 'lk-bob');
        call.subscriber.onTrack?.call(
          RTCTrackEvent(
            streams: [FakeMediaStream('PA_bob|TR_bv')],
            track: native.track!,
            receiver: FakeReceiver(
              native.receiverId,
              native.track,
              owner: call.subscriber,
            ),
          ),
        );
        call.flush();
        call.remoteJoins();

        expect(call.remote()!.videoStream, isNull);
        expect(call.remote(bob)!.videoStream!.id, 'PA_bob|TR_bv');
        expect(
          call.backend.cryptors.liveLabels,
          contains(receiverLabel(bob, MediaKind.video)),
        );
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(ann, MediaKind.video))),
        );
      });
    });

    test('a membership that goes drops its track and unsubscribes', () {
      runLiveKitCall((call) {
        call.server.others.add(
          remoteParticipant('PA_ann', 'lk-ann', tracks: [remoteTrack('TR_a')]),
        );
        call.join();
        call.encrypt();
        call.remoteJoins();
        call.remoteTrackArrives(participantSid: 'PA_ann', trackSid: 'TR_a');

        call.engine.removeRemoteParticipant(ann);
        call.flush();

        final last = call.server.subscriptions.last;
        expect(last.subscribe, isFalse);
        expect(last.trackSids, ['TR_a']);
        expect(
          call.backend.cryptors.liveLabels,
          isNot(contains(receiverLabel(ann, MediaKind.audio))),
        );
      });
    });

    test('a membership without an identity is not this provider', () {
      runLiveKitCall((call) {
        call.join();
        call.encrypt();

        call.engine.updateRemoteParticipant(ann, {
          'sessionId': 'cloudflare-session',
          'encrypted': true,
        }, membershipEventId: r'$membership');
        call.flush();

        expect(call.remote(), isNull);
      });
    });
  });

  group('sending media', () {
    test('a remote sends media once its participant has a published track', () {
      runLiveKitCall((call) {
        call.server.others.add(remoteParticipant('PA_ann', 'lk-ann'));
        call.join();
        call.remoteJoins();
        expect(call.remote()!.sendingMedia, isFalse);
        final emitted = call.emitted.length;

        call.server.participantUpdate([
          remoteParticipant(
            'PA_ann',
            'lk-ann',
            tracks: [remoteTrack('TR_a')],
            version: 2,
          ),
        ]);
        call.flush();

        expect(call.remote()!.sendingMedia, isTrue);
        expect(call.emitted.length, greaterThan(emitted));
      });
    });
  });

  group('video', () {
    test('showVideo(null) mutes and clears the sender track', () {
      runLiveKitCall((call) {
        call.join();
        call.encrypt();
        final camera = call.camera;
        final sender = call.senderOf(camera);

        call.wait(call.engine.setCameraEnabled(false));

        expect(sender.track, isNull);
        final mute = call.server.sentOf(SignalRequest_Message.mute).single.mute;
        expect(mute.sid, 'TR_${camera.id}');
        expect(mute.muted, isTrue);
        expect(call.engine.localFociInfo!['videoEnabled'], isFalse);

        call.wait(call.engine.setCameraEnabled(true));

        expect(sender.track, same(call.camera));
        final unmute = call.server.sentOf(SignalRequest_Message.mute).last.mute;
        expect(unmute.muted, isFalse);
        expect(call.server.addTracks, hasLength(2));
        expect(call.engine.localFociInfo!['videoEnabled'], isTrue);
      }, kind: CallKind.video);
    });
  });

  group('ratings', () {
    test('our rating goes out as a reliable quality data packet', () {
      runLiveKitCall((call) {
        call.join();
        final channel = call.publisher.dataChannel('_reliable')!;

        call.connection.sendRating(CallQuality.degraded);

        final packet = DataPacket.fromBuffer(channel.sentBinary.last);
        expect(packet.user.topic, 'quality');
        expect(utf8.decode(packet.user.payload), '{"quality":"degraded"}');
      });
    });

    test('no rating is sent while the data channel is not open', () {
      runLiveKitCall((call) {
        call.join();
        final channel = call.publisher.dataChannel('_reliable')!..connecting();

        call.connection.sendRating(CallQuality.poor);
        expect(channel.sentBinary, isEmpty);

        channel.opens();
        call.connection.sendRating(CallQuality.poor);
        expect(channel.sentBinary, hasLength(1));
      });
    });

    void annRates(LiveKitCall call, String quality) {
      final channel = FakeDataChannel('_reliable', 1, negotiated: false);
      call.subscriber.emitDataChannel(channel);
      channel.receiveBinary(
        DataPacket(
          participantIdentity: 'lk-ann',
          user: UserPacket(
            topic: 'quality',
            payload: utf8.encode('{"quality":"$quality"}'),
          ),
        ).writeToBuffer(),
      );
      call.flush();
    }

    test("a peer's rating clears when its participant leaves LiveKit or "
        'rejoins with a new sid', () {
      runLiveKitCall((call) {
        call.server.others.add(remoteParticipant('PA_ann', 'lk-ann'));
        call.join();
        call.remoteJoins();

        annRates(call, 'poor');
        expect(call.remote()!.weakConnection, isTrue);
        call.server.participantUpdate([remoteParticipant('PA_ann2', 'lk-ann')]);
        call.flush();
        expect(call.remote()!.weakConnection, isFalse);

        annRates(call, 'poor');
        expect(call.remote()!.weakConnection, isTrue);
        call.server.participantUpdate([
          ParticipantInfo(
            sid: 'PA_ann2',
            identity: 'lk-ann',
            state: ParticipantInfo_State.DISCONNECTED,
          ),
        ]);
        call.flush();
        expect(call.remote()!.weakConnection, isFalse);
      });
    });

    test("a peer's rating clears on a full reconnect", () {
      runLiveKitCall((call) {
        call.server.others.add(remoteParticipant('PA_ann', 'lk-ann'));
        call.join();
        call.connectPeers();
        call.remoteJoins();
        annRates(call, 'degraded');
        expect(call.remote()!.weakConnection, isTrue);

        call.server.leaves(LeaveRequest_Action.RECONNECT);
        call.elapse(const Duration(seconds: 1));

        expect(call.backend.peerConnections, hasLength(4));
        expect(call.remote()!.weakConnection, isFalse);
      });
    });

    test("a peer's rating maps to its device through the identity", () {
      runLiveKitCall((call) {
        call.join();
        call.remoteJoins();
        final channel = FakeDataChannel('_reliable', 1, negotiated: false);
        call.subscriber.emitDataChannel(channel);

        channel.receiveBinary(
          DataPacket(
            participantIdentity: 'lk-ann',
            user: UserPacket(
              topic: 'quality',
              payload: utf8.encode('{"quality":"poor"}'),
            ),
          ).writeToBuffer(),
        );
        call.flush();

        expect(call.remote()!.weakConnection, isTrue);
      });
    });
  });

  group('closing', () {
    test('close sends leave and disposes both peer connections', () {
      runLiveKitCall((call) {
        call.join();
        final socket = call.server.socket;
        final publisher = call.publisher;
        final subscriber = call.subscriber;

        call.leave();

        final leave = socket.sentOf(SignalRequest_Message.leave).single.leave;
        expect(leave.reason, DisconnectReason.CLIENT_INITIATED);
        expect(socket.closed, isTrue);
        expect(publisher.disposed, isTrue);
        expect(subscriber.disposed, isTrue);
      });
    });

    test('a hang-up disposes the peer connections and cryptors without '
        'waiting on the socket to close', () {
      runLiveKitCall((call) {
        call.join();
        call.encrypt();
        final socket = call.server.socket..closeGate = Completer<void>();
        final publisher = call.publisher;
        final subscriber = call.subscriber;

        call.leave();

        expect(socket.sentOf(SignalRequest_Message.leave), hasLength(1));
        expect(socket.closed, isTrue);
        expect(publisher.disposed, isTrue);
        expect(subscriber.disposed, isTrue);
        expect(call.backend.cryptors.live, isEmpty);
        socket.closeGate!.complete();
      });
    });

    test('a hang-up while the signal connects leaves no open socket', () {
      runLiveKitCall((call) {
        call.server.connectGate = Completer<void>();
        call.startJoin();
        expect(call.server.connects, hasLength(1));

        call.leave();
        call.server.connectGate!.complete();
        call.elapse(const Duration(seconds: 30));

        expect(call.server.socket.closed, isTrue);
        expect(call.server.socket.sent, isEmpty);
        expect(call.backend.peerConnections, isEmpty);
      });
    });

    test('local media that fails to start is not reported as a publish', () {
      runLiveKitCall((call) {
        final lines = recordDebugPrints();
        call.backend.captureError = StateError('no microphone');

        expect(call.join, throwsA(isA<StateError>()));
        call.elapse(const Duration(seconds: 30));

        expect(
          lines.where((l) => l.startsWith('zuno/caught: publish to LiveKit')),
          isEmpty,
        );
        expect(call.server.connects, hasLength(1));
      });
    });

    test('a hang-up while the grant is pending opens no signal', () {
      runLiveKitCall((call) {
        call.module.gate = Completer<void>();
        call.startJoin();

        call.leave();
        call.module.gate!.complete();
        call.flush();

        expect(call.server.connects, isEmpty);
        expect(call.backend.peerConnections, isEmpty);
      });
    });
  });
}
