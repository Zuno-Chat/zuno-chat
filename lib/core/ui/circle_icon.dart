import 'package:flutter/material.dart';

class CircleIcon extends StatelessWidget {
  final IconData icon;
  final bool danger;

  const CircleIcon(this.icon, {super.key, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: danger ? colors.error : colors.onSurface,
        ),
      ),
    );
  }
}
