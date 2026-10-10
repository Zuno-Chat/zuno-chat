import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/call_audio_route.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/calls/models/call_quality.dart';
import '../../../core/calls/models/call_status.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/corner_snap.dart';
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
  final CallAudioRoute audioRoute;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onHangUp;
  final VoidCallback onMinimize;
  final String? confirmName;
  final VoidCallback? onConfirmPerson;
  final SnapCorner selfCorner;
  final ValueChanged<SnapCorner> onSelfCornerChanged;

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
    required this.audioRoute,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
    required this.onHangUp,
    required this.onMinimize,
    required this.selfCorner,
    required this.onSelfCornerChanged,
    this.confirmName,
    this.onConfirmPerson,
  });

  List<CallViewParticipant> get present => connecting ? const [] : remote;

  CallStatus get status {
    final local = this.local;
    return callStatus(
      calling: calling,
      connecting: connecting,
      someoneHere: present.isNotEmpty,
      keysPending:
          local == null || [...present, local].any((p) => p.encrypting),
    );
  }

  @override
  State<CallView> createState() => _CallViewState();
}

const _selfSize = Size(100, 140);
const _gap = 12.0;
const _edge = 12.0;

class _CallViewState extends State<CallView> {
  static const _minimizeReserve = 64.0;

  DateTime? _encryptingSince;
  CornerSpots? _selfSpots;

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
    final self = widget.kind == CallKind.video && !group && !widget.connecting
        ? widget.local
        : null;
    final shownQuality = widget.connecting ? CallQuality.good : widget.quality;
    final pill =
        !widget.reconnecting &&
        ConnectionQualityPill.labelFor(shownQuality) != null;
    final confirmName = widget.confirmName;
    final onConfirmPerson = widget.onConfirmPerson;
    final confirm =
        confirmName != null &&
        onConfirmPerson != null &&
        present.length == 1 &&
        !widget.reconnecting &&
        !pill;
    final padding = MediaQuery.paddingOf(context);
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
        bottom: false,
        child: group ? _group(present) : _voice(present.firstOrNull, status),
      );
    }

    return Scaffold(
      backgroundColor: fullVideo || group ? Colors.black : null,
      body: CustomMultiChildLayout(
        delegate: _CallLayout(
          stageUnderDock: fullVideo,
          padding: padding,
          selfCorner: widget.selfCorner,
          onSelfSpots: (spots) => _selfSpots = spots,
        ),
        children: [
          LayoutId(id: _Slot.stage, child: stage),
          LayoutId(
            id: _Slot.notice,
            child: widget.reconnecting
                ? const ReconnectingNotice()
                : const SizedBox.shrink(),
          ),
          if (self != null)
            LayoutId(
              id: _Slot.self,
              child: CornerSnap(
                key: const ValueKey('self'),
                corner: widget.selfCorner,
                onCornerChanged: widget.onSelfCornerChanged,
                spots: () => _selfSpots!,
                child: Semantics(
                  label: 'You',
                  excludeSemantics: true,
                  child: ParticipantTile(
                    participant: self.participant,
                    renderer: self.renderer,
                    user: self.user,
                    showStatus: false,
                  ),
                ),
              ),
            ),
          LayoutId(
            id: _Slot.header,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                if (fullVideo) _header(present.single, status),
                _minimizeButton(overVideo: fullVideo),
              ],
            ),
          ),
          LayoutId(
            id: _Slot.dock,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, _gap, 8, padding.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: _gap,
                children: [
                  if (pill)
                    ConnectionQualityPill(
                      key: const ValueKey('quality'),
                      quality: shownQuality,
                    ),
                  if (confirm)
                    Padding(
                      key: const ValueKey('confirm'),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ConfirmPersonPill(
                        name: confirmName,
                        overVideo: fullVideo,
                        onPressed: onConfirmPerson,
                      ),
                    ),
                  FittedBox(
                    key: const ValueKey('controls'),
                    fit: BoxFit.scaleDown,
                    child: CallControls(
                      kind: widget.kind,
                      micMuted: local?.participant.audioMuted ?? false,
                      cameraOn: local?.participant.videoEnabled ?? false,
                      audioRoute: widget.audioRoute,
                      enabled: local != null,
                      overVideo: fullVideo,
                      onToggleMute: widget.onToggleMute,
                      onToggleCamera: widget.onToggleCamera,
                      onSwitchCamera: widget.onSwitchCamera,
                      onToggleSpeaker: widget.onToggleSpeaker,
                      onHangUp: widget.onHangUp,
                    ),
                  ),
                ],
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
        toneSeed: user?.id ?? roomToneSeed(room),
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

  Widget _minimizeButton({required bool overVideo}) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: widget.onMinimize,
      tooltip: 'Minimize call',
      icon: const Icon(Icons.close_fullscreen),
      style: IconButton.styleFrom(
        backgroundColor: overVideo
            ? Colors.black54
            : colors.surfaceContainerHighest,
        foregroundColor: overVideo ? Colors.white : colors.onSurface,
      ),
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
          padding: const EdgeInsets.fromLTRB(_minimizeReserve, 10, 16, 8),
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

enum _Slot { stage, notice, self, header, dock }

class _CallLayout extends MultiChildLayoutDelegate {
  final bool stageUnderDock;
  final EdgeInsets padding;
  final SnapCorner selfCorner;
  final ValueSetter<CornerSpots> onSelfSpots;

  _CallLayout({
    required this.stageUnderDock,
    required this.padding,
    required this.selfCorner,
    required this.onSelfSpots,
  });

  @override
  void performLayout(Size size) {
    final screen = BoxConstraints.tight(size);
    final dock = layoutChild(
      _Slot.dock,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    final dockTop = size.height - dock.height;
    positionChild(_Slot.dock, Offset(0, dockTop));
    layoutChild(
      _Slot.stage,
      stageUnderDock ? screen : BoxConstraints.tight(Size(size.width, dockTop)),
    );
    layoutChild(_Slot.notice, screen);

    final selfShown = hasChild(_Slot.self);
    final area = Rect.fromLTRB(
      math.max(padding.left, _edge),
      math.max(padding.top, _edge),
      size.width - math.max(padding.right, _edge),
      dockTop,
    );
    final headerWidth = math.max(
      0.0,
      area.width - (selfShown ? _selfSize.width + _gap : 0),
    );
    final header = layoutChild(
      _Slot.header,
      BoxConstraints.tightFor(width: headerWidth),
    );
    positionChild(_Slot.header, area.topLeft);

    if (!selfShown) return;
    final spots = CornerSpots(
      bounds: area,
      size: _selfSize,
      keepClear: area.topLeft & (header + const Offset(0, _gap)),
    );
    onSelfSpots(spots);
    layoutChild(_Slot.self, BoxConstraints.tight(_selfSize));
    positionChild(_Slot.self, spots.of(selfCorner));
  }

  @override
  bool shouldRelayout(_CallLayout oldDelegate) =>
      oldDelegate.stageUnderDock != stageUnderDock ||
      oldDelegate.padding != padding ||
      oldDelegate.selfCorner != selfCorner;
}
