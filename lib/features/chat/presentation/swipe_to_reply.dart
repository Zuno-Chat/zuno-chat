import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/zuno_motion.dart';

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  static const threshold = 56.0;
  static const maxDrag = 72.0;

  const SwipeToReply({super.key, required this.child, required this.onReply});

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  final _offset = ValueNotifier<double>(0);
  AnimationController? _spring;
  double _springFrom = 0;
  bool _armed = false;

  @override
  void dispose() {
    _spring?.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails details) {
    _spring?.stop();
    final next = (_offset.value + details.delta.dx).clamp(
      -SwipeToReply.maxDrag,
      0.0,
    );
    _offset.value = next;
    final armed = next <= -SwipeToReply.threshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
  }

  void _release({required bool fire}) {
    if (fire && _armed) widget.onReply();
    _armed = false;
    if (_offset.value == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = 0;
      return;
    }
    final spring = _spring ??= _createSpring();
    _springFrom = _offset.value;
    spring.forward(from: 0);
  }

  AnimationController _createSpring() {
    final controller = AnimationController(
      vsync: this,
      duration: ZunoDurations.fast,
    );
    controller.addListener(() {
      _offset.value =
          _springFrom * (1 - Curves.easeOut.transform(controller.value));
    });
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: (_) => _release(fire: true),
      onHorizontalDragCancel: () => _release(fire: false),
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        child: widget.child,
        builder: (context, dx, child) => Stack(
          children: [
            Positioned.fill(
              child: dx == 0
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Icon(
                          Icons.reply_outlined,
                          color: color.withValues(
                            alpha: (-dx / SwipeToReply.threshold).clamp(
                              0.0,
                              1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Transform.translate(offset: Offset(dx, 0), child: child),
          ],
        ),
      ),
    );
  }
}
