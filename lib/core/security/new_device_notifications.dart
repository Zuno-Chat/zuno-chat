import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/l10n.dart';
import '../notifications/local_notifications.dart';

bool _isNewDeviceTap(NotificationResponse response) =>
    decodeNotificationPayload(response.payload)?['type'] ==
    newDevicePayloadType;

class NewDeviceNotifications {
  NewDeviceNotifications._();
  static final instance = NewDeviceNotifications._();

  LocalNotifications get _notifications => LocalNotifications.instance;

  Stream<void> get onTap =>
      _notifications.onResponse.where(_isNewDeviceTap).map((_) {});

  Future<void> show({
    required String deviceId,
    required String title,
    required String body,
  }) async {
    await _notifications.initialize();
    final l10n = deviceLocalizations();
    await _notifications.plugin.show(
      id: _notificationIdFor(deviceId),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          securityChannelId,
          l10n.notificationsChannelNewSignIns,
          channelDescription: l10n.notificationsChannelNewSignInsDescription,
          category: AndroidNotificationCategory.status,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({'type': newDevicePayloadType, 'deviceId': deviceId}),
    );
  }

  int _notificationIdFor(String deviceId) =>
      'device:$deviceId'.hashCode & 0x7fffffff;
}
