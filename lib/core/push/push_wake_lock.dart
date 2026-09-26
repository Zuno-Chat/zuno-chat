import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/push_wakelock');
const _fcmChannel = MethodChannel('zuno/wake_lock');

Future<void> releasePushWakeLock() async {
  try {
    await _channel.invokeMethod<void>('release');
  } catch (e) {
    debugPrint('zuno/push: wakelock release skipped ($e)');
  }
}

Future<void> releaseFcmPushWakeLock() async {
  try {
    await _fcmChannel.invokeMethod<void>('releasePush');
  } catch (e) {
    debugPrint('zuno/push: FCM wakelock release skipped ($e)');
  }
}
