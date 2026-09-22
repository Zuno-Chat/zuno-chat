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
}
