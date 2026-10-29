import 'package:flutter/material.dart';

import 'zuno_colors.dart';
import 'zuno_motion.dart';

class PageDots extends StatelessWidget {
  final int count;
  final int current;
  final double dot;
  final bool overMedia;

  const PageDots({
    required this.count,
    required this.current,
    this.dot = 6,
    this.overMedia = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final on = overMedia ? onMediaColor : colors.primary;
    final off = overMedia ? onMediaFaintColor : colors.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: dot,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: ZunoDurations.motion(context, ZunoDurations.fast),
            width: i == current ? dot * 2.5 : dot,
            height: dot,
            decoration: BoxDecoration(
              color: i == current ? on : off,
              borderRadius: BorderRadius.circular(dot / 2),
            ),
          ),
      ],
    );
  }
}
