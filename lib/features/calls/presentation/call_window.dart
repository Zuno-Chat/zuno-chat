import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/call_picture_in_picture.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/zuno_motion.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_bar.dart';
import 'participant_tile.dart';

enum CallWindowCorner { topLeft, topRight, bottomLeft, bottomRight }

const _margin = 8.0;

final _corners = Expando<CallWindowCorner>('call window corner');

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

Offset callWindowOrigin(CallWindowCorner corner, Rect bounds, Size window) =>
    Offset(
      switch (corner) {
        CallWindowCorner.topLeft || CallWindowCorner.bottomLeft => bounds.left,
        _ => bounds.right - window.width,
      },
      switch (corner) {
        CallWindowCorner.topLeft || CallWindowCorner.topRight => bounds.top,
        _ => math.max(bounds.top, bounds.bottom - window.height),
      },
    );

CallWindowCorner nearestCallWindowCorner(Offset center, Rect bounds) {
  final left = center.dx < bounds.center.dx;
  final top = center.dy < bounds.center.dy;
  return switch ((top, left)) {
    (true, true) => CallWindowCorner.topLeft,
    (true, false) => CallWindowCorner.topRight,
    (false, true) => CallWindowCorner.bottomLeft,
    (false, false) => CallWindowCorner.bottomRight,
  };
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

class _CallWindowState extends State<CallWindow>
    with SingleTickerProviderStateMixin {
  late final _snap = AnimationController(
    vsync: this,
    duration: ZunoDurations.standard,
  );
  late final _settling = CurvedAnimation(
    parent: _snap,
    curve: Curves.fastOutSlowIn,
  );
  final _offset = ValueNotifier(Offset.zero);
  late final _motion = Listenable.merge([_settling, _offset]);

  CallWindowCorner get _corner =>
      _corners[widget.call] ?? CallWindowCorner.topRight;

  Offset get _shownOffset => _offset.value * (1 - _settling.value);

  @override
  void dispose() {
    _settling.dispose();
    _snap.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _grab() {
    _offset.value = _shownOffset;
    _snap.value = 0;
  }

  void _release(Rect bounds, Size size) {
    final released = callWindowOrigin(_corner, bounds, size) + _offset.value;
    final corner = nearestCallWindowCorner(
      released + size.center(Offset.zero),
      bounds,
    );
    _corners[widget.call] = corner;
    _offset.value = released - callWindowOrigin(corner, bounds, size);
    if (MediaQuery.disableAnimationsOf(context)) {
      _snap.value = 1;
    } else {
      _snap.forward(from: 0);
    }
  }

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
    final size = callWindowSize(
      MediaQuery.sizeOf(context),
      pictureInPictureAspect(
        renderer?.videoWidth ?? 0,
        renderer?.videoHeight ?? 0,
      ),
    );
    final bounds = callWindowBounds(
      widget.area,
      padding: MediaQuery.paddingOf(context),
      viewInsets: MediaQuery.viewInsetsOf(context),
      keepClear: keepClear,
    );
    return TweenAnimationBuilder<Size?>(
      tween: SizeTween(begin: size, end: size),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : ZunoDurations.standard,
      curve: Curves.fastOutSlowIn,
      builder: (context, shape, tile) => AnimatedBuilder(
        animation: _motion,
        builder: (context, tile) {
          final origin =
              callWindowOrigin(_corner, bounds, shape!) + _shownOffset;
          return Positioned(
            left: origin.dx,
            top: origin.dy,
            width: shape.width,
            height: shape.height,
            child: tile!,
          );
        },
        child: tile,
      ),
      child: Semantics(
        container: true,
        button: true,
        label: returnToCallLabel,
        value: roomTitle(widget.call.session.room),
        onTap: widget.onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: widget.onTap,
          onPanStart: (_) => _grab(),
          onPanUpdate: (details) => _offset.value += details.delta,
          onPanEnd: (_) => _release(bounds, size),
          onPanCancel: () => _release(bounds, size),
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
