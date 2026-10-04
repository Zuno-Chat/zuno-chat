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

class ForwardExitPageRoute extends MaterialPageRoute<Never> {
  ForwardExitPageRoute({required super.builder, super.settings});

  static void popForward(BuildContext context) {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null && !route.isCurrent) {
      navigator.removeRoute(route);
      return;
    }
    if (route is ForwardExitPageRoute) route._forwardRequested = true;
    navigator.pop();
  }

  static const _exitCurve = FlippedCurve(Curves.easeOut);

  static final _leaving = Tween<Offset>(
    begin: const Offset(-1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: _exitCurve));

  static final _arriving = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(1, 0),
  ).chain(CurveTween(curve: _exitCurve));

  final _entrance = ProxyAnimation();
  final _exit = ProxyAnimation(kAlwaysCompleteAnimation);
  bool _forwardRequested = false;
  bool _exitingForward = false;

  @override
  Duration get reverseTransitionDuration => _exitingForward
      ? ZunoDurations.standard
      : super.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _exitingForward ? _arriveFromTrailingEdge : super.delegatedTransition;

  @override
  void install() {
    super.install();
    _entrance.parent = animation;
  }

  @override
  bool didPop(Never? result) {
    final forwardRequested = _forwardRequested;
    _forwardRequested = false;
    if (forwardRequested &&
        !willHandlePopInternally &&
        animation!.isCompleted &&
        secondaryAnimation!.isDismissed) {
      _exitingForward = true;
      _entrance.parent = kAlwaysCompleteAnimation;
      _exit.parent = animation;
    }
    return super.didPop(result);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = super.buildTransitions(
      context,
      _entrance,
      secondaryAnimation,
      child,
    );
    if (MediaQuery.disableAnimationsOf(context)) return entering;
    return SlideTransition(
      position: _exit.drive(_leaving),
      textDirection: Directionality.of(context),
      child: entering,
    );
  }

  static Widget? _arriveFromTrailingEdge(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return null;
    return SlideTransition(
      position: secondaryAnimation.drive(_arriving),
      textDirection: Directionality.of(context),
      child: child,
    );
  }
}
