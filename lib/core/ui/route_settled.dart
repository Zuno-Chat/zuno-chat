import 'package:flutter/material.dart';

mixin RouteSettled<T extends StatefulWidget> on State<T> {
  Animation<double>? _routeAnimation;
  bool _routeSettled = false;

  bool get routeSettled => _routeSettled;

  void onRouteSettled();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watchRoute();
    });
  }

  void _watchRoute() {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _settle();
      return;
    }
    _routeAnimation = animation;
    animation.addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    if (mounted) _settle();
  }

  void _settle() {
    if (_routeSettled) return;
    _routeSettled = true;
    onRouteSettled();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }
}
