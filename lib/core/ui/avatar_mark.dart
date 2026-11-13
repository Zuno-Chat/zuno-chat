import 'package:flutter/material.dart';

Color avatarMarkRingColor(BuildContext context) =>
    Material.maybeOf(context)?.color ?? Theme.of(context).colorScheme.surface;

class MarkedAvatar extends StatelessWidget {
  final Widget avatar;
  final Widget? mark;

  const MarkedAvatar({required this.avatar, this.mark, super.key});

  @override
  Widget build(BuildContext context) {
    final mark = this.mark;
    if (mark == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(right: -2, bottom: -2, child: mark),
      ],
    );
  }
}

class AvatarMark extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? semanticLabel;

  const AvatarMark({
    required this.icon,
    required this.color,
    this.semanticLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: avatarMarkRingColor(context),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 12, color: color, semanticLabel: semanticLabel),
  );
}
