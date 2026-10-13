import 'package:flutter/material.dart';

class LaunchRoute<T> extends MaterialPageRoute<T> {
  LaunchRoute({required super.builder, this.instant = true});

  final bool instant;

  @override
  Duration get transitionDuration =>
      instant ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => instant
      ? const Duration(milliseconds: 300)
      : super.reverseTransitionDuration;
}

Route<T> pageRoute<T>({
  required bool instant,
  required WidgetBuilder builder,
}) => LaunchRoute<T>(builder: builder, instant: instant);
