import 'package:flutter/material.dart';

import 'zuno_colors.dart';
import 'zuno_theme.dart';

enum MediaPillSize {
  small(
    radius: ZunoRadius.small,
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    iconSize: 14,
    gap: 2,
  ),
  regular(
    radius: ZunoRadius.compact,
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    iconSize: 16,
    gap: 6,
  );

  final double radius;
  final EdgeInsets padding;
  final double iconSize;
  final double gap;

  const MediaPillSize({
    required this.radius,
    required this.padding,
    required this.iconSize,
    required this.gap,
  });

  TextStyle textStyle(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final base = switch (this) {
      small => text.labelSmall!,
      regular => text.labelMedium!,
    };
    return base.copyWith(color: onMediaColor);
  }
}

class MediaPill extends StatelessWidget {
  final Widget child;
  final MediaPillSize size;

  const MediaPill({
    required this.child,
    this.size = MediaPillSize.regular,
    super.key,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: mediaScrimColor,
      borderRadius: BorderRadius.circular(size.radius),
    ),
    child: Padding(
      padding: size.padding,
      child: IconTheme.merge(
        data: IconThemeData(size: size.iconSize, color: onMediaColor),
        child: DefaultTextStyle.merge(
          style: size.textStyle(context),
          child: child,
        ),
      ),
    ),
  );
}
