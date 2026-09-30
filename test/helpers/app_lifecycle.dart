import 'package:flutter/widgets.dart';

const _lifecycle = [
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

void moveLifecycleTo(WidgetsBinding binding, AppLifecycleState target) {
  if (binding.lifecycleState == null) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  var at = _lifecycle.indexOf(binding.lifecycleState!);
  final to = _lifecycle.indexOf(target);
  while (at != to) {
    at += at < to ? 1 : -1;
    binding.handleAppLifecycleStateChanged(_lifecycle[at]);
  }
}
