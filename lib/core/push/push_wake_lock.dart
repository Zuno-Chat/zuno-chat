import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/push_wakelock');
const _fcmChannel = MethodChannel('zuno/wake_lock');

bool _holdsWakeLocks(PlatformCapabilities? capabilities) =>
    (capabilities ?? ambientCapabilities).headlessWakeLocks;

Future<void> releasePushWakeLock({PlatformCapabilities? capabilities}) async {
  if (!_holdsWakeLocks(capabilities)) return;
  try {
    await _channel.invokeMethod<void>('release');
  } catch (e) {
    debugPrint('zuno/push: wakelock release skipped ($e)');
  }
}

Future<void> releaseFcmPushWakeLock({
  PlatformCapabilities? capabilities,
}) async {
  if (!_holdsWakeLocks(capabilities)) return;
  try {
    await _fcmChannel.invokeMethod<void>('releasePush');
  } catch (e) {
    debugPrint('zuno/push: FCM wakelock release skipped ($e)');
  }
}
