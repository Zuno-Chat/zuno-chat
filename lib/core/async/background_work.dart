import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;

import '../errors/device_log.dart';
import '../platform/platform_capabilities.dart';

typedef BackgroundRunner = Future<R> Function<R>(
  FutureOr<R> Function() work, {
  String? debugName,
});

BackgroundRunner _runner = runInIsolate;

Future<R> runInBackground<R>(
  FutureOr<R> Function() work, {
  String? debugName,
}) => _runner(work, debugName: debugName);

Future<R> computeInBackground<Q, R>(
  FutureOr<R> Function(Q message) callback,
  Q message, {
  String? debugLabel,
}) => runInBackground(() => callback(message), debugName: debugLabel);

@visibleForTesting
set backgroundRunner(BackgroundRunner runner) => _runner = runner;

@visibleForTesting
Future<R> runInIsolate<R>(
  FutureOr<R> Function() work, {
  String? debugName,
  bool release = kReleaseMode,
  PlatformCapabilities? capabilities,
}) => Isolate.run(
  () =>
      runWithDeviceLogFloor(work, release: release, capabilities: capabilities),
  debugName: debugName,
);
