import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

import 'fake_webrtc.dart';

typedef RemoteUpdate = ({
  VoipParticipantId id,
  Map<String, Object?> fociInfo,
  Set<MediaKind> wanted,
  String? membershipEventId,
});

class FakeCallConnection implements CallConnection {
  FakeCallConnection(this.host, {this.journal});

  final CallConnectionHost host;
  final List<String>? journal;

  @override
  Map<String, Object?>? handle;
  VideoSlot? slot;
  bool publishesVideoSlot = true;
  bool Function(Map<String, Object?> fociInfo) matches = (_) => true;
  final senders = <MediaKind, FakeSender>{};
  final shownVideo = <MediaStreamTrack?>[];
  final remoteUpdates = <RemoteUpdate>[];
  final removedRemotes = <VoipParticipantId>[];
  final sending = <VoipParticipantId>{};
  var joins = 0;
  var senderCount = 0;
  bool closed = false;
  Object? joinError;
  Completer<void>? closeGate;

  @override
  VideoSlot get videoSlot =>
      slot ??
      (senders.containsKey(MediaKind.video) ? VideoSlot.ready : VideoSlot.none);

  @override
  Future<void> join() async {
    joins++;
    if (joinError case final error?) throw error;
    await host.publishLocalMedia(publish);
    host.reportStatus(CallEngineStatus.connected);
  }

  Future<bool> publish() async {
    final send = host.localSend;
    senderCount++;
    final audio = senders[MediaKind.audio] = FakeSender(
      'fake-audio-$senderCount',
      send.microphone,
    );
    await host.adoptSender(MediaKind.audio, audio);
    if (!publishesVideoSlot && !send.sendCamera) return true;
    final video = senders[MediaKind.video] = FakeSender(
      'fake-video-$senderCount',
      send.sendCamera ? send.camera : null,
    );
    await host.adoptSender(MediaKind.video, video);
    return true;
  }

  @override
  Future<bool> showVideo(MediaStreamTrack? camera) async {
    shownVideo.add(camera);
    final sender = senders[MediaKind.video];
    if (sender == null) {
      if (camera == null) return true;
      final published = senders[MediaKind.video] = FakeSender(
        'fake-video-$senderCount',
        camera,
      );
      await host.adoptSender(MediaKind.video, published);
      return true;
    }
    await sender.replaceTrack(camera);
    if (camera != null) await host.adoptSender(MediaKind.video, sender);
    return true;
  }

  @override
  RTCRtpSender? sender(MediaKind kind) => senders[kind];

  final openPeerConnections = <RTCPeerConnection>[];

  @override
  List<RTCPeerConnection> get peerConnections => [...openPeerConnections];

  @override
  bool updateRemote(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
    Set<MediaKind> wanted, {
    required String? membershipEventId,
  }) {
    remoteUpdates.add((
      id: id,
      fociInfo: fociInfo,
      wanted: wanted,
      membershipEventId: membershipEventId,
    ));
    return matches(fociInfo);
  }

  @override
  bool sendingMedia(VoipParticipantId id) => sending.contains(id);

  @override
  void removeRemote(VoipParticipantId id) => removedRemotes.add(id);

  var observedStats = 0;
  final sentRatings = <CallQuality>[];

  @override
  void observeStats(Iterable<StatsReport> reports) => observedStats++;

  @override
  void sendRating(CallQuality rating) => sentRatings.add(rating);

  @override
  Future<void> close() async {
    closed = true;
    await closeGate?.future;
    journal?.add('connection closed');
  }
}

class FakeCallConnections implements CallConnectionOpener {
  FakeCallConnections({this.journal});

  final List<String>? journal;
  Completer<void>? openGate;
  Object? openError;
  Object? rediscoverError;
  Completer<void>? rediscoverGate;
  final joinErrors = <Object?>[];
  final rediscoveries = <bool>[];
  final opened = <FakeCallConnection>[];

  FakeCallConnection get connection => opened.single;

  @override
  Future<CallConnection> open(
    CallSpec spec,
    CallConnectionHost host, {
    bool rediscover = false,
  }) async {
    rediscoveries.add(rediscover);
    if (rediscover) await rediscoverGate?.future;
    if (rediscover && rediscoverError != null) throw rediscoverError!;
    final connection = FakeCallConnection(host, journal: journal)
      ..joinError = joinErrors.isEmpty ? null : joinErrors.removeAt(0);
    opened.add(connection);
    await openGate?.future;
    if (openError case final error?) throw error;
    return connection;
  }
}
