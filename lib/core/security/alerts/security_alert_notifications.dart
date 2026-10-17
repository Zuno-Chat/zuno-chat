import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/l10n.dart';
import '../../notifications/local_notifications.dart';

bool _isSecurityAlertTap(NotificationResponse response) =>
    decodeNotificationPayload(response.payload)?['type'] ==
    securityAlertPayloadType;

class SecurityAlertNotifications {
  SecurityAlertNotifications._();
  static final instance = SecurityAlertNotifications._();

  LocalNotifications get _notifications => LocalNotifications.instance;

  Stream<void> get onTap =>
      _notifications.onResponse.where(_isSecurityAlertTap).map((_) {});

  Future<void> show({
    required String alertKey,
    required String title,
    required String body,
  }) async {
    await _notifications.initialize();
    final l10n = deviceLocalizations();
    await _notifications.plugin.show(
      id: alertKey.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          securityChannelId,
          l10n.notificationsChannelSecurity,
          channelDescription: l10n.notificationsChannelSecurityDescription,
          category: AndroidNotificationCategory.status,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({'type': securityAlertPayloadType}),
    );
  }
}
