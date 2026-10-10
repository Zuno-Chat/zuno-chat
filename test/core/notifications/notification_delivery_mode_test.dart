import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';

void main() {
  test('UnifiedPush and background sync need Android to stop '
      'battery-optimising the app; Google services and Apple push do not', () {
    expect(
      {
        for (final mode in NotificationDeliveryMode.values)
          mode: deliveryDependsOnBatteryExemption(mode),
      },
      {
        NotificationDeliveryMode.fcm: false,
        NotificationDeliveryMode.unifiedPush: true,
        NotificationDeliveryMode.backgroundService: true,
        NotificationDeliveryMode.apns: false,
      },
    );
  });

  test('no method shouts or uses a contraction', () {
    for (final mode in NotificationDeliveryMode.values) {
      for (final text in [mode.label, mode.description]) {
        expect(text, isNot(contains('!')), reason: '$mode');
        expect(text, isNot(contains("'")), reason: '$mode');
      }
    }
  });

  test('Google services and Apple push keep a log of recent pushes', () {
    expect(
      {
        for (final mode in NotificationDeliveryMode.values)
          mode: deliveryLogsEachPush(mode),
      },
      {
        NotificationDeliveryMode.fcm: true,
        NotificationDeliveryMode.unifiedPush: false,
        NotificationDeliveryMode.backgroundService: false,
        NotificationDeliveryMode.apns: true,
      },
    );
  });
}
