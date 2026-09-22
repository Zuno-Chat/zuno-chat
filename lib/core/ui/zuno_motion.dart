import 'package:flutter/material.dart';

abstract final class ZunoDurations {
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 250);
  static const page = Duration(milliseconds: 300);
}

class ZunoSlideTransitionsBuilder extends PageTransitionsBuilder {
  const ZunoSlideTransitionsBuilder();

  static final _incoming = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.fastOutSlowIn));

  static final _outgoing = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-0.3, 0),
  ).chain(CurveTween(curve: Curves.fastOutSlowIn));

  @override
  Duration get transitionDuration => ZunoDurations.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: animation.drive(_incoming),
      child: SlideTransition(
        position: secondaryAnimation.drive(_outgoing),
        child: child,
      ),
    );
  }
}
