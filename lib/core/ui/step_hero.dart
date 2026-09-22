import 'package:flutter/material.dart';

class StepHero extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final ImageProvider? image;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool compact;

  const StepHero({
    super.key,
    this.icon,
    this.child,
    this.image,
    this.onTap,
    this.semanticLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = compact ? 72.0 : 112.0;
    final image = this.image;
    final content = image != null
        ? Ink.image(image: image, fit: BoxFit.cover, width: size, height: size)
        : Center(
            child:
                child ??
                Icon(
                  icon,
                  size: compact ? 32 : 48,
                  color: colors.onSecondaryContainer,
                ),
          );
    final circle = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: colors.secondaryContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
    if (semanticLabel == null && onTap == null) return circle;
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: circle,
    );
  }
}
