import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'zuno_motion.dart';

enum SnapCorner {
  topLeft('top left'),
  topRight('top right'),
  bottomLeft('bottom left'),
  bottomRight('bottom right');

  final String label;

  const SnapCorner(this.label);
}

class CornerSpots {
  final Rect bounds;
  final Size size;
  final Rect? keepClear;

  const CornerSpots({required this.bounds, required this.size, this.keepClear});

  Offset of(SnapCorner corner) {
    final lowest = math.max(bounds.top, bounds.bottom - size.height);
    final spot = Offset(
      switch (corner) {
        SnapCorner.topLeft || SnapCorner.bottomLeft => bounds.left,
        _ => bounds.right - size.width,
      },
      switch (corner) {
        SnapCorner.topLeft || SnapCorner.topRight => bounds.top,
        _ => lowest,
      },
    );
    final keepClear = this.keepClear;
    if (keepClear != null &&
        (spot & size).overlaps(keepClear) &&
        keepClear.bottom <= lowest) {
      return Offset(spot.dx, keepClear.bottom);
    }
    return spot;
  }

  SnapCorner nearest(Offset origin) {
    final center = origin + size.center(Offset.zero);
    final left = center.dx < bounds.center.dx;
    final top = center.dy < bounds.center.dy;
    return switch ((top, left)) {
      (true, true) => SnapCorner.topLeft,
      (true, false) => SnapCorner.topRight,
      (false, true) => SnapCorner.bottomLeft,
      (false, false) => SnapCorner.bottomRight,
    };
  }
}

class CornerSnap extends StatefulWidget {
  final SnapCorner corner;
  final ValueChanged<SnapCorner> onCornerChanged;
  final ValueGetter<CornerSpots> spots;
  final VoidCallback? onTap;
  final Widget child;

  const CornerSnap({
    required this.corner,
    required this.onCornerChanged,
    required this.spots,
    required this.child,
    this.onTap,
    super.key,
  });

  @override
  State<CornerSnap> createState() => _CornerSnapState();
}

class _CornerSnapState extends State<CornerSnap>
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

  void _release() {
    final spots = widget.spots();
    final released = spots.of(widget.corner) + _shownOffset;
    _settle(spots, spots.nearest(released), released);
  }

  void _moveTo(SnapCorner corner) {
    final spots = widget.spots();
    _settle(spots, corner, spots.of(widget.corner) + _shownOffset);
  }

  void _settle(CornerSpots spots, SnapCorner corner, Offset from) {
    _offset.value = from - spots.of(corner);
    if (corner != widget.corner) widget.onCornerChanged(corner);
    if (MediaQuery.disableAnimationsOf(context)) {
      _snap.value = 1;
    } else {
      _snap.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      customSemanticsActions: {
        for (final corner in SnapCorner.values)
          if (corner != widget.corner)
            CustomSemanticsAction(label: 'Move to ${corner.label}'): () =>
                _moveTo(corner),
      },
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, box) =>
            Transform.translate(offset: _shownOffset, child: box),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: widget.onTap,
          onPanStart: (_) => _grab(),
          onPanUpdate: (details) => _offset.value += details.delta,
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: widget.child,
        ),
      ),
    );
  }
}
