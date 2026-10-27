import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'zuno_colors.dart';

class FrostedSurface extends StatelessWidget {
  final Widget child;
  final bool circle;
  final bool highlighted;

  const FrostedSurface({
    required this.child,
    this.circle = false,
    this.highlighted = false,
    super.key,
  });

  static final _blur = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);
  static const _edge = BorderSide(color: frostedEdgeColor);
  static const _shadows = [
    BoxShadow(color: frostedShadowColor, blurRadius: 14, offset: Offset(0, 4)),
  ];

  @override
  Widget build(BuildContext context) {
    final OutlinedBorder shape = circle
        ? const CircleBorder(side: _edge)
        : const StadiumBorder(side: _edge);
    final frosted = BackdropFilter.grouped(
      filter: _blur,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: highlighted ? frostedHighlightColor : frostedFillColor,
          shape: shape,
        ),
        child: child,
      ),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: _shadows),
      child: circle
          ? ClipOval(child: frosted)
          : ClipRRect(
              borderRadius: BorderRadius.circular(1000),
              child: frosted,
            ),
    );
  }
}
