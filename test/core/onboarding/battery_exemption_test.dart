import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';

void main() {
  Future<bool> needs(
    NotificationDeliveryMode mode, {
    bool zunoExempt = true,
    bool distributorRestricted = false,
  }) => needsBatteryExemptionFor(
    mode,
    zunoIgnoresBatteryOptimizations: () async => zunoExempt,
    distributorBatteryRestricted: () async => distributorRestricted,
  );

  test('FCM never needs an exemption, whatever the phone says', () async {
    expect(
      await needs(
        NotificationDeliveryMode.fcm,
        zunoExempt: false,
        distributorRestricted: true,
      ),
      isFalse,
    );
  });

  test(
    'UnifiedPush is fine when both Zuno and the distributor are exempt',
    () async {
      expect(await needs(NotificationDeliveryMode.unifiedPush), isFalse);
    },
  );

  test('UnifiedPush needs the step when Zuno is not exempt', () async {
    expect(
      await needs(NotificationDeliveryMode.unifiedPush, zunoExempt: false),
      isTrue,
    );
  });

  test(
    'UnifiedPush needs the step when only the distributor is restricted',
    () async {
      expect(
        await needs(
          NotificationDeliveryMode.unifiedPush,
          distributorRestricted: true,
        ),
        isTrue,
      );
    },
  );

  test('background sync only cares about Zuno itself', () async {
    expect(
      await needs(
        NotificationDeliveryMode.backgroundService,
        distributorRestricted: true,
      ),
      isFalse,
    );
    expect(
      await needs(
        NotificationDeliveryMode.backgroundService,
        zunoExempt: false,
      ),
      isTrue,
    );
  });

  test('a probe that throws is treated as no exemption needed', () async {
    expect(
      await needsBatteryExemptionFor(
        NotificationDeliveryMode.unifiedPush,
        zunoIgnoresBatteryOptimizations: () async => throw Exception('no'),
        distributorBatteryRestricted: () async => true,
      ),
      isFalse,
    );
  });
}
