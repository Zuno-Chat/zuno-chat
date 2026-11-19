import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'zuno_motion.dart';

const _zoomedScale = 2.5;
const _maxScale = 5.0;
const _flingFriction = 0.0000135;

class Zoomable extends StatefulWidget {
  final VoidCallback? onTap;
  final ValueChanged<bool>? onZoomChanged;
  final Widget child;

  const Zoomable({
    this.onTap,
    this.onZoomChanged,
    required this.child,
    super.key,
  });

  @override
  State<Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<Zoomable>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _zoomAnimation = AnimationController(vsync: this)
    ..addListener(_stepZoom);
  var _from = (scale: 1.0, offset: Offset.zero);
  var _to = (scale: 1.0, offset: Offset.zero);
  Offset _doubleTapAt = Offset.zero;
  double _pinchStartScale = 1;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_followZoom);
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transform.dispose();
    super.dispose();
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  Offset get _offset {
    final translation = _transform.value.getTranslation();
    return Offset(translation.x, translation.y);
  }

  void _followZoom() {
    final zoomed = _scale > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  GestureDisposition? _claimDrag(Offset move) {
    if (!_zoomed) return null;
    if (move.dx.abs() <= move.dy.abs()) return GestureDisposition.accepted;
    final room = move.dx > 0
        ? -_offset.dx
        : _offset.dx - context.size!.width * (1 - _scale);
    return room > precisionErrorTolerance
        ? GestureDisposition.accepted
        : GestureDisposition.rejected;
  }

  void _setView(double scale, Offset offset) {
    final size = context.size!;
    final x = offset.dx.clamp(size.width * (1 - scale), 0.0);
    final y = offset.dy.clamp(size.height * (1 - scale), 0.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _stepZoom() {
    final t = _zoomAnimation.value;
    _setView(
      lerpDouble(_from.scale, _to.scale, t)!,
      Offset.lerp(_from.offset, _to.offset, t)!,
    );
  }

  void _animateTo(double scale, Offset offset, Duration duration, Curve curve) {
    _from = (scale: _scale, offset: _offset);
    _to = (scale: scale, offset: offset);
    _zoomAnimation
      ..value = 0
      ..animateTo(1, duration: duration, curve: curve);
  }

  void _toggleZoom() {
    final scale = _zoomed ? 1.0 : _zoomedScale;
    _animateTo(
      scale,
      _doubleTapAt * (1 - scale),
      ZunoDurations.motion(context, ZunoDurations.standard),
      Curves.easeOut,
    );
  }

  void _onPinchStart(ScaleStartDetails details) {
    _zoomAnimation.stop();
    _pinchStartScale = _scale;
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    final scale = (_pinchStartScale * details.scale).clamp(1.0, _maxScale);
    final scene = _transform.toScene(
      details.localFocalPoint - details.focalPointDelta,
    );
    _setView(scale, details.localFocalPoint - scene * scale);
  }

  void _onPinchEnd(ScaleEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    if (!_zoomed ||
        details.pointerCount > 0 ||
        velocity.distance < kMinFlingVelocity ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final from = _offset;
    final seconds =
        math.log(10 / velocity.distance) / math.log(_flingFriction / 100);
    _animateTo(
      _scale,
      Offset(
        FrictionSimulation(_flingFriction, from.dx, velocity.dx).finalX,
        FrictionSimulation(_flingFriction, from.dy, velocity.dy).finalX,
      ),
      Duration(milliseconds: (seconds * 1000).round()),
      Curves.decelerate,
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
    onDoubleTap: _toggleZoom,
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _PinchRecognizer:
            GestureRecognizerFactoryWithHandlers<_PinchRecognizer>(
              () => _PinchRecognizer(claimDrag: _claimDrag, debugOwner: this),
              (recognizer) => recognizer
                ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
                ..onStart = _onPinchStart
                ..onUpdate = _onPinchUpdate
                ..onEnd = _onPinchEnd,
            ),
      },
      child: ValueListenableBuilder(
        valueListenable: _transform,
        builder: (context, view, child) =>
            Transform(transform: view, child: child),
        child: widget.child,
      ),
    ),
  );
}

class _PinchRecognizer extends ScaleGestureRecognizer {
  final GestureDisposition? Function(Offset move) claimDrag;
  Offset _downAt = Offset.zero;

  _PinchRecognizer({required this.claimDrag, super.debugOwner});

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent) {
      _downAt = event.position;
      if (pointerCount > 1) resolve(GestureDisposition.accepted);
    } else if (event is PointerMoveEvent &&
        (event.position - _downAt).distance >
            computeHitSlop(event.kind, gestureSettings)) {
      final claim = claimDrag(event.position - _downAt);
      if (claim != null) resolve(claim);
    }
  }
}
