import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/calls/models/call_quality.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_title.dart';
import 'call_controls.dart';
import 'call_stage.dart';
import 'call_status_line.dart';
import 'call_status_widgets.dart';
import 'participant_tile.dart';

class CallViewParticipant {
  final CallEngineParticipant participant;
  final RTCVideoRenderer? renderer;
  final User? user;
  final bool encrypting;

  const CallViewParticipant({
    required this.participant,
    required this.renderer,
    required this.user,
    required this.encrypting,
  });
}

class CallView extends StatefulWidget {
  final Room room;
  final CallKind kind;
  final bool connecting;
  final bool calling;
  final CallViewParticipant? local;
  final List<CallViewParticipant> remote;
  final DateTime? talkingSince;
  final bool reconnecting;
  final CallQuality quality;
  final bool speakerOn;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onHangUp;

  const CallView({
    super.key,
    required this.room,
    required this.kind,
    required this.connecting,
    required this.calling,
    required this.local,
    required this.remote,
    required this.talkingSince,
    required this.reconnecting,
    required this.quality,
    required this.speakerOn,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
    required this.onHangUp,
  });

  List<CallViewParticipant> get present => connecting ? const [] : remote;

  CallStatus get status {
    final present = this.present;
    if (present.isEmpty) {
      if (calling) return CallStatus.calling;
      return connecting ? CallStatus.connecting : CallStatus.waiting;
    }
    final local = this.local;
    if (local == null) return CallStatus.encrypting;
    return [...present, local].any((p) => p.encrypting)
        ? CallStatus.encrypting
        : CallStatus.talking;
  }

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  static const _controlsReserve = 92.0;
  static const _pillReserve = 34.0;

  DateTime? _encryptingSince;

  @override
  void initState() {
    super.initState();
    _trackEncrypting();
  }

  @override
  void didUpdateWidget(CallView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _trackEncrypting();
  }

  void _trackEncrypting() {
    if (widget.status == CallStatus.encrypting) {
      _encryptingSince ??= DateTime.now();
    } else {
      _encryptingSince = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final present = widget.present;
    final status = widget.status;
    final group = present.length > 1;
    final fullVideo =
        present.length == 1 &&
        (widget.kind == CallKind.video ||
            present.single.participant.videoEnabled);
    final self = widget.kind == CallKind.video && !group ? widget.local : null;
    final shownQuality = widget.connecting ? CallQuality.good : widget.quality;
    final pill =
        !widget.reconnecting &&
        ConnectionQualityPill.labelFor(shownQuality) != null;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final local = widget.local;

    final Widget stage;
    if (fullVideo) {
      final other = present.single;
      stage = ParticipantTile(
        participant: other.participant,
        renderer: other.renderer,
        user: other.user,
        showStatus: false,
        showMuted: false,
        borderRadius: 0,
        background: Colors.black,
      );
    } else {
      stage = SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: _controlsReserve + (pill ? _pillReserve : 0),
          ),
          child: group ? _group(present) : _voice(present.firstOrNull, status),
        ),
      );
    }

    return Scaffold(
      backgroundColor: fullVideo || group ? Colors.black : null,
      body: Stack(
        children: [
          Positioned.fill(key: const ValueKey('stage'), child: stage),
          Positioned.fill(
            key: const ValueKey('notice'),
            child: widget.reconnecting
                ? const ReconnectingNotice()
                : const SizedBox.shrink(),
          ),
          Positioned.fill(
            key: const ValueKey('overlay'),
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  if (fullVideo)
                    Positioned(
                      key: const ValueKey('header'),
                      left: 0,
                      top: 0,
                      right: self == null ? 0 : 112,
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: _header(present.single, status),
                      ),
                    ),
                  if (self != null)
                    Positioned(
                      key: const ValueKey('self'),
                      right: 0,
                      top: 0,
                      width: 100,
                      height: 140,
                      child: ParticipantTile(
                        participant: self.participant,
                        renderer: self.renderer,
                        user: null,
                        showStatus: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (pill)
            Positioned(
              key: const ValueKey('quality'),
              left: 0,
              right: 0,
              bottom: safeBottom + _controlsReserve,
              child: Center(
                child: ConnectionQualityPill(quality: shownQuality),
              ),
            ),
          Positioned(
            key: const ValueKey('controls'),
            left: 8,
            right: 8,
            bottom: safeBottom + 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CallControls(
                kind: widget.kind,
                micMuted: local?.participant.audioMuted ?? false,
                cameraOn: local?.participant.videoEnabled ?? false,
                speakerOn: widget.speakerOn,
                enabled: !widget.connecting,
                overVideo: fullVideo,
                onToggleMute: widget.onToggleMute,
                onToggleCamera: widget.onToggleCamera,
                onSwitchCamera: widget.onSwitchCamera,
                onToggleSpeaker: widget.onToggleSpeaker,
                onHangUp: widget.onHangUp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voice(CallViewParticipant? other, CallStatus status) {
    final room = widget.room;
    final user = other?.user;
    final name = user?.calcDisplayname() ?? roomTitle(room);
    return VoiceCallStage(
      avatarBuilder: (radius) => MxcAvatar(
        client: room.client,
        avatarUrl: user?.avatarUrl ?? room.avatar,
        fallbackText: name,
        toneSeed: user?.id ?? room.id,
        radius: radius,
      ),
      name: name,
      status: status,
      talkingSince: widget.talkingSince,
      encryptingSince: _encryptingSince,
      remoteMuted: other?.participant.audioMuted ?? false,
      remoteWeak: other?.participant.lowBandwidth ?? false,
    );
  }

  Widget _header(CallViewParticipant other, CallStatus status) =>
      VideoCallHeader(
        name: other.user?.calcDisplayname() ?? roomTitle(widget.room),
        status: status,
        talkingSince: widget.talkingSince,
        encryptingSince: _encryptingSince,
        remoteMuted: other.participant.audioMuted,
        remoteWeak: other.participant.lowBandwidth,
      );

  Widget _group(List<CallViewParticipant> others) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final since = widget.talkingSince;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  roomTitle(widget.room),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              if (since != null)
                Flexible(
                  child: CallTimerSuffix(since: since, style: titleStyle),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CallGrid(
              tiles: [
                for (final entry in [...others, ?widget.local])
                  ParticipantTile(
                    key: ValueKey(entry.participant.id),
                    participant: entry.participant,
                    renderer: entry.renderer,
                    user: entry.user,
                    encrypting: entry.encrypting,
                    name: entry.participant.isLocal
                        ? 'You'
                        : entry.user?.calcDisplayname(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
