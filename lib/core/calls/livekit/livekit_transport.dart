import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../async/serial_lock.dart';
import '../../errors/best_effort.dart';
import '../media/video_codec.dart';
import '../media/webrtc_backend.dart';
import 'proto/livekit_rtc.pb.dart';

class LiveKitNegotiationAbandoned implements Exception {
  const LiveKitNegotiationAbandoned();

  @override
  String toString() => 'LiveKitNegotiationAbandoned';
}

const _answerDeadline = Duration(seconds: 15);

Map<String, dynamic> liveKitConfiguration(
  Iterable<ICEServer> servers, {
  required bool relayOnly,
}) => {
  'iceServers': [
    for (final server in servers)
      {
        'urls': server.urls.toList(),
        if (server.username.isNotEmpty) 'username': server.username,
        if (server.credential.isNotEmpty) 'credential': server.credential,
      },
  ],
  'sdpSemantics': 'unified-plan',
  if (relayOnly) 'iceTransportPolicy': 'relay',
};

class LiveKitTransport {
  LiveKitTransport._(this.pc, this._target, this._send);

  static Future<LiveKitTransport> open(
    WebRtcBackend webRtc, {
    required SignalTarget target,
    required Map<String, dynamic> configuration,
    required bool Function(SignalRequest request) send,
  }) async {
    final transport = LiveKitTransport._(
      await webRtc.createPeerConnection(configuration),
      target,
      send,
    );
    transport.pc
      ..onIceCandidate = transport._trickle
      ..onConnectionState = transport._changed;
    return transport;
  }

  final RTCPeerConnection pc;
  final SignalTarget _target;
  final bool Function(SignalRequest request) _send;
  final _negotiation = SerialLock();
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _described = false;
  bool _disposed = false;
  Completer<SessionDescription>? _answer;
  RTCPeerConnectionState? state;
  void Function()? onStateChanged;

  void _changed(RTCPeerConnectionState state) {
    if (_disposed) return;
    this.state = state;
    onStateChanged?.call();
  }

  void _trickle(RTCIceCandidate candidate) {
    if (_disposed || candidate.candidate == null) return;
    _send(
      SignalRequest(
        trickle: TrickleRequest(
          candidateInit: jsonEncode({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
          target: _target,
        ),
      ),
    );
  }

  Future<void> addRemoteCandidate(String candidateInit) async {
    final candidate = _candidateFrom(candidateInit);
    if (candidate == null) return;
    await _negotiation.run(() async {
      if (_disposed) return;
      if (!_described) {
        _pendingCandidates.add(candidate);
        return;
      }
      await pc.addCandidate(candidate);
    });
  }

  Future<void> _describeRemote(RTCSessionDescription description) async {
    await pc.setRemoteDescription(description);
    _described = true;
    final pending = List.of(_pendingCandidates);
    _pendingCandidates.clear();
    if (_disposed) return;
    await Future.wait([
      for (final candidate in pending)
        runBestEffort(
          () => pc.addCandidate(candidate),
          label: 'add a buffered LiveKit ICE candidate',
        ),
    ]);
  }

  Future<void> offer({bool iceRestart = false}) => _negotiation.run(() async {
    if (_disposed) throw const LiveKitNegotiationAbandoned();
    if (iceRestart) await pc.restartIce();
    final offer = await pc.createOffer(const <String, dynamic>{});
    if (_disposed) throw const LiveKitNegotiationAbandoned();
    await pc.setLocalDescription(offer);
    final answered = _answer = Completer<SessionDescription>();
    final sent = _send(
      SignalRequest(
        offer: SessionDescription(type: offer.type, sdp: offer.sdp),
      ),
    );
    final SessionDescription answer;
    try {
      if (!sent || _disposed) throw const LiveKitNegotiationAbandoned();
      answer = await answered.future.timeout(_answerDeadline);
    } finally {
      if (identical(_answer, answered)) _answer = null;
    }
    if (_disposed) throw const LiveKitNegotiationAbandoned();
    await _describeRemote(
      RTCSessionDescription(withSentVideoParams(answer.sdp), answer.type),
    );
  });

  Completer<SessionDescription>? _takeAnswer() {
    final answered = _answer;
    _answer = null;
    return answered != null && !answered.isCompleted ? answered : null;
  }

  void answerArrived(SessionDescription answer) =>
      _takeAnswer()?.complete(answer);

  void abandon() =>
      _takeAnswer()?.completeError(const LiveKitNegotiationAbandoned());

  Future<void> answer(SessionDescription offer) => _negotiation.run(() async {
    if (_disposed) return;
    await _describeRemote(RTCSessionDescription(offer.sdp, offer.type));
    if (_disposed) return;
    final answer = await pc.createAnswer();
    if (_disposed) return;
    await pc.setLocalDescription(answer);
    if (_disposed) return;
    _send(
      SignalRequest(
        answer: SessionDescription(
          type: answer.type,
          sdp: answer.sdp,
          id: offer.id,
        ),
      ),
    );
  });

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    abandon();
    _pendingCandidates.clear();
    pc
      ..onIceCandidate = null
      ..onConnectionState = null
      ..onTrack = null
      ..onRemoveTrack = null
      ..onDataChannel = null;
    await runBestEffort(pc.dispose, label: 'dispose a LiveKit peer connection');
  }
}

RTCIceCandidate? _candidateFrom(String candidateInit) {
  final Object? json;
  try {
    json = jsonDecode(candidateInit);
  } on FormatException {
    return null;
  }
  if (json case {'candidate': final String candidate}) {
    return RTCIceCandidate(
      candidate,
      switch (json['sdpMid']) {
        final String mid => mid,
        _ => null,
      },
      switch (json['sdpMLineIndex']) {
        final int index => index,
        _ => null,
      },
    );
  }
  return null;
}
