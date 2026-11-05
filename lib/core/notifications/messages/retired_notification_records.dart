import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../platform/platform_capabilities.dart';
import 'notification_room_cache.dart';
import 'notification_thread_store.dart';

const _retiredThreadsKey = 'notifications.threads';

Future<void> moveRetiredNotificationRecords(
  SharedPreferences prefs,
  PlatformCapabilities capabilities,
) async {
  if (prefs.getString(_retiredThreadsKey) case final retired?) {
    await _moveThreads(retired);
    await prefs.remove(_retiredThreadsKey);
  }
  if (!capabilities.instantPushNotices &&
      prefs.containsKey(notificationRoomCacheKey)) {
    await prefs.remove(notificationRoomCacheKey);
  }
}

Future<void> _moveThreads(String retired) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(retired);
  } on FormatException {
    return;
  }
  if (decoded is! Map) return;
  for (final MapEntry(:key, :value) in decoded.entries) {
    final thread = StoredNotificationThread.fromJson('$key', value);
    if (thread == null || thread.lines.isEmpty) continue;
    await NotificationThreadStore.instance.write(
      thread,
      showing: () async => null,
    );
  }
}
