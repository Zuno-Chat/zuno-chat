import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_status_widgets.dart';

class ParticipantTile extends StatefulWidget {
  final CallEngineParticipant participant;
  final RTCVideoRenderer? renderer;
  final User? user;
  final bool encrypting;
  final String? name;
  final bool showStatus;
  final bool showMuted;
  final double borderRadius;
  final Color? background;

  const ParticipantTile({
    required this.participant,
    required this.renderer,
    this.user,
    this.encrypting = false,
    this.name,
    this.showStatus = true,
    this.showMuted = true,
    this.borderRadius = ZunoRadius.medium,
    this.background,
    super.key,
  });

  @override
  State<ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends State<ParticipantTile> {
  static const _revealSettle = Duration(milliseconds: 100);
  static const _revealFallback = Duration(milliseconds: 400);

  bool _switchingCamera = false;
  Timer? _revealTimer;

  CallEngineParticipant get participant => widget.participant;
  bool get encrypting => widget.encrypting;
  User? get user => widget.user;

  @override
  void initState() {
    super.initState();
    widget.renderer?.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(ParticipantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderer != widget.renderer) {
      oldWidget.renderer?.removeListener(_onFrame);
      widget.renderer?.addListener(_onFrame);
    }
    if (participant.frontCamera != oldWidget.participant.frontCamera) {
      _switchingCamera = true;
      _scheduleReveal(_revealFallback);
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    widget.renderer?.removeListener(_onFrame);
    super.dispose();
  }

  void _onFrame() {
    if (_switchingCamera) _scheduleReveal(_revealSettle);
  }

  void _scheduleReveal(Duration after) {
    _revealTimer?.cancel();
    _revealTimer = Timer(after, () {
      _revealTimer = null;
      if (mounted) setState(() => _switchingCamera = false);
    });
  }

  Widget? _status() {
    if (!widget.showStatus) return null;
    if (encrypting) {
      return Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: EncryptingLabel(),
        ),
      );
    }
    if (!participant.isLocal && participant.lowBandwidth) {
      return const CallBadge(label: 'Weak connection');
    }
    return null;
  }

  Widget? _identity() {
    final name = widget.name;
    final muted = widget.showMuted && participant.audioMuted;
    if (name == null) {
      if (!muted) return null;
      return const Icon(Icons.mic_off_outlined, color: Colors.white, size: 18);
    }
    return CallBadge(
      icon: muted ? Icons.mic_off_outlined : null,
      label: name,
      semanticLabel: muted ? '$name is muted' : name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final renderer = widget.renderer;
    final showVideo = participant.videoEnabled && renderer != null;
    final status = _status();
    final identity = _identity();
    final colors = Theme.of(context).colorScheme;
    final content = ColoredBox(
      color: widget.background ?? colors.surfaceContainerHigh,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_switchingCamera)
            const SizedBox.shrink()
          else if (showVideo)
            RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirror: participant.frontCamera,
            )
          else
            Center(
              child: user != null
                  ? MxcAvatar(
                      client: user!.room.client,
                      avatarUrl: user!.avatarUrl,
                      fallbackText: user!.calcDisplayname(),
                      radius: 36,
                    )
                  : CircleAvatar(
                      radius: 36,
                      backgroundColor: colors.surfaceContainerHighest,
                      foregroundColor: colors.onSurfaceVariant,
                      child: const Icon(Icons.person_outline, size: 32),
                    ),
            ),
          if (status != null)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: Align(alignment: Alignment.topRight, child: status),
            ),
          if (identity != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Align(alignment: Alignment.bottomLeft, child: identity),
            ),
        ],
      ),
    );
    if (widget.borderRadius == 0) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: content,
    );
  }
}
