import 'package:flutter/material.dart';

class LaunchRoute<T> extends MaterialPageRoute<T> {
  LaunchRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

Route<T> pageRoute<T>({required bool instant, required WidgetBuilder builder}) {
  if (instant) return LaunchRoute<T>(builder: builder);
  return MaterialPageRoute<T>(builder: builder);
}
