import 'dart:math';

import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/push_wakelock');
const _refinementChannel = MethodChannel('zuno/wake_lock');
const refinementWakeLockCap = Duration(seconds: 8);

final _refinementTagPrefix = 'push_refine_${Random().nextInt(1 << 30)}';
var _refinements = 0;

bool _holdsWakeLocks(PlatformCapabilities? capabilities) =>
    (capabilities ?? ambientCapabilities).headlessWakeLocks;

typedef PushWakeLockRelease = Future<void> Function({String? key});

Future<void> releasePushWakeLock({
  String? key,
  PlatformCapabilities? capabilities,
}) async {
  if (!_holdsWakeLocks(capabilities)) return;
  try {
    await _channel.invokeMethod<void>(
      'release',
      key == null ? null : {'key': key},
    );
  } catch (e, s) {
    reportCaught('push wake lock release', e, s);
  }
}

Future<bool> nativePushAppInFront({PlatformCapabilities? capabilities}) async {
  if (!_holdsWakeLocks(capabilities)) return true;
  try {
    return await _channel.invokeMethod<bool>('appInFront') ?? true;
  } catch (e, s) {
    reportCaught('push app in front check', e, s);
    return true;
  }
}

Future<void> keepAwakeWhile(
  Future<void> work, {
  PlatformCapabilities? capabilities,
}) async {
  if (!_holdsWakeLocks(capabilities)) return work;
  final tag = '${_refinementTagPrefix}_${_refinements++}';
  final acquiring = _refinementLock('acquire', {
    'tag': tag,
    'timeoutMs': refinementWakeLockCap.inMilliseconds,
  });
  try {
    await work;
  } finally {
    await acquiring;
    await _refinementLock('release', {'tag': tag});
  }
}

Future<void> _refinementLock(String method, Map<String, Object> args) async {
  try {
    await _refinementChannel.invokeMethod<void>(method, args);
  } catch (e, s) {
    reportCaught('push refinement wake lock $method', e, s);
  }
}
