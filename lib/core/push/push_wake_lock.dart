import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/push_wakelock');

Future<void> releasePushWakeLock() async {
  try {
    await _channel.invokeMethod<void>('release');
  } catch (e) {
    debugPrint('zuno/push: wakelock release skipped ($e)');
  }
}
