import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart' show kReleaseMode;

import '../platform/platform_capabilities.dart';
import 'caught_errors.dart';

const _androidLogWarn = 5;

const _setMinimumPriority = '__android_log_set_minimum_priority';

R runWithDeviceLogFloor<R>(
  R Function() body, {
  bool release = kReleaseMode,
  PlatformCapabilities? capabilities,
  void Function() raiseNativeFloor = _raiseLiblogFloor,
}) {
  if (!release) return body();
  if ((capabilities ?? ambientCapabilities).nativeLogFloor) {
    try {
      raiseNativeFloor();
    } catch (error, stack) {
      reportCaught('raise the device log floor', error, stack);
    }
  }
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
  );
}

void _raiseLiblogFloor() {
  final liblog = DynamicLibrary.open('liblog.so');
  if (!liblog.providesSymbol(_setMinimumPriority)) return;
  liblog.lookupFunction<Int32 Function(Int32), int Function(int)>(
    _setMinimumPriority,
  )(_androidLogWarn);
}
