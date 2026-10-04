import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';

void main() {
  group('which modes need Android to stop battery-optimising the app', () {
    test('UnifiedPush does — it has to do a network fetch on wake', () {
      expect(
        deliveryDependsOnBatteryExemption(NotificationDeliveryMode.unifiedPush),
        isTrue,
      );
    });

    test('background sync does — Doze pauses the service otherwise', () {
      expect(
        deliveryDependsOnBatteryExemption(
          NotificationDeliveryMode.backgroundService,
        ),
        isTrue,
      );
    });

    test('FCM does not', () {
      expect(
        deliveryDependsOnBatteryExemption(NotificationDeliveryMode.fcm),
        isFalse,
      );
    });

    test('Apple push does not — iOS has no battery exemption to grant', () {
      expect(
        deliveryDependsOnBatteryExemption(NotificationDeliveryMode.apns),
        isFalse,
      );
    });

    test(
      'FCM does not depend on a battery exemption; both real fallbacks do',
      () {
        expect(
          deliveryDependsOnBatteryExemption(NotificationDeliveryMode.fcm),
          isFalse,
        );
        expect(
          deliveryDependsOnBatteryExemption(
            NotificationDeliveryMode.unifiedPush,
          ),
          isTrue,
        );
        expect(
          deliveryDependsOnBatteryExemption(
            NotificationDeliveryMode.backgroundService,
          ),
          isTrue,
        );
      },
    );
  });

  group('copy', () {
    test('Apple push is named plainly and says what it needs', () {
      expect(NotificationDeliveryMode.apns.label, 'Apple push');
      expect(
        NotificationDeliveryMode.apns.description,
        'Instant, through Apple, with no setup',
      );
    });

    test('the Android methods keep their names', () {
      expect(NotificationDeliveryMode.fcm.label, 'Google services');
      expect(NotificationDeliveryMode.unifiedPush.label, 'UnifiedPush');
      expect(
        NotificationDeliveryMode.backgroundService.label,
        'Background sync',
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
