import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/call_picture_in_picture.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/corner_snap.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/zuno_motion.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_bar.dart';
import 'participant_tile.dart';

const _margin = 8.0;

final _corners = Expando<SnapCorner>('call window corner');

Rect callWindowBounds(
  Size area, {
  required EdgeInsets padding,
  required EdgeInsets viewInsets,
  double keepClear = 0,
}) => Rect.fromLTRB(
  padding.left + _margin,
  padding.top + kToolbarHeight + _margin,
  area.width - padding.right - _margin,
  area.height -
      math.max(viewInsets.bottom + keepClear, padding.bottom) -
      _margin,
);

Size callWindowSize(Size screen, PictureInPictureAspect aspect) {
  final width = (screen.shortestSide * 0.3).clamp(96.0, 160.0);
  final height = (width * aspect.height / aspect.width).clamp(
    width * 9 / 16,
    width * 16 / 9,
  );
  return Size(width, height);
}

class CallWindow extends StatefulWidget {
  final ActiveCallController call;
  final CallEngineParticipant remote;
  final Size area;
  final VoidCallback onTap;

  const CallWindow({
    required this.call,
    required this.remote,
    required this.area,
    required this.onTap,
    super.key,
  });

  @override
  State<CallWindow> createState() => _CallWindowState();
}

class _CallWindowState extends State<CallWindow> {
  SnapCorner get _corner => _corners[widget.call] ?? SnapCorner.topRight;

  @override
  Widget build(BuildContext context) {
    final renderer = widget.call.rendererFor(widget.remote.id);
    final keepClear = KeepClearScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([?renderer, ?keepClear]),
      builder: (context, _) =>
          _window(context, renderer, keepClear?.bottom ?? 0),
    );
  }

  Widget _window(
    BuildContext context,
    RTCVideoRenderer? renderer,
    double keepClear,
  ) {
    final bounds = callWindowBounds(
      widget.area,
      padding: MediaQuery.paddingOf(context),
      viewInsets: MediaQuery.viewInsetsOf(context),
      keepClear: keepClear,
    );
    final size = callWindowSize(
      MediaQuery.sizeOf(context),
      pictureInPictureAspect(
        renderer?.videoWidth ?? 0,
        renderer?.videoHeight ?? 0,
      ),
    );
    return TweenAnimationBuilder<Size?>(
      tween: SizeTween(begin: size, end: size),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : ZunoDurations.standard,
      curve: Curves.fastOutSlowIn,
      builder: (context, shape, window) {
        final spot = CornerSpots(bounds: bounds, size: shape!).of(_corner);
        return Positioned(
          left: spot.dx,
          top: spot.dy,
          width: shape.width,
          height: shape.height,
          child: window!,
        );
      },
      child: CornerSnap(
        corner: _corner,
        onCornerChanged: (corner) =>
            setState(() => _corners[widget.call] = corner),
        spots: () => CornerSpots(bounds: bounds, size: size),
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          label: returnToCallLabel,
          value: roomTitle(widget.call.session.room),
          onTap: widget.onTap,
          excludeSemantics: true,
          child: Theme(
            data: zunoDarkTheme,
            child: Material(
              color: Colors.black,
              elevation: 6,
              borderRadius: BorderRadius.circular(ZunoRadius.medium),
              child: ParticipantTile(
                participant: widget.remote,
                renderer: renderer,
                user: widget.call.userFor(widget.remote),
                encrypting: widget.call.encrypting(widget.remote),
                showStatus: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
