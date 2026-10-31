import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/zuno_motion.dart';

const _dismissDistance = 100.0;
const _dismissVelocity = 800.0;
const _fadeDistance = 300.0;

class ViewerDismiss extends StatefulWidget {
  final bool enabled;
  final ValueChanged<double> onProgress;
  final VoidCallback onDismiss;
  final Widget child;

  const ViewerDismiss({
    required this.enabled,
    required this.onProgress,
    required this.onDismiss,
    required this.child,
    super.key,
  });

  @override
  State<ViewerDismiss> createState() => _ViewerDismissState();
}

class _ViewerDismissState extends State<ViewerDismiss>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this)
    ..addListener(_report);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _report() =>
      widget.onProgress((_offset.value / _fadeDistance).clamp(0, 1));

  void _onUpdate(DragUpdateDetails details) =>
      _offset.value = math.max(0, _offset.value + details.delta.dy);

  void _onEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_offset.value > _dismissDistance || velocity > _dismissVelocity) {
      widget.onDismiss();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = 0;
    } else {
      _offset.animateTo(
        0,
        duration: ZunoDurations.standard,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return GestureDetector(
      onVerticalDragUpdate: enabled ? _onUpdate : null,
      onVerticalDragEnd: enabled ? _onEnd : null,
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, _offset.value), child: child),
        child: widget.child,
      ),
    );
  }
}
