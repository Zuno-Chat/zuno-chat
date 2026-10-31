import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/delivery/notification_delivery_mode.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  Future<bool> needs(
    NotificationDeliveryMode mode, {
    bool zunoExempt = true,
    bool distributorRestricted = false,
    PlatformCapabilities? capabilities,
  }) => needsBatteryExemptionFor(
    mode,
    zunoIgnoresBatteryOptimizations: () async => zunoExempt,
    distributorBatteryRestricted: () async => distributorRestricted,
    capabilities: capabilities ?? androidCapabilities,
  );

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

  test('Google services and background sync only care about Zuno '
      'itself', () async {
    for (final mode in [
      NotificationDeliveryMode.fcm,
      NotificationDeliveryMode.backgroundService,
    ]) {
      expect(
        await needs(mode, distributorRestricted: true),
        isFalse,
        reason: mode.name,
      );
      expect(await needs(mode, zunoExempt: false), isTrue, reason: mode.name);
    }
  });

  test('a probe that throws is treated as no exemption needed', () async {
    expect(
      await needsBatteryExemptionFor(
        NotificationDeliveryMode.unifiedPush,
        zunoIgnoresBatteryOptimizations: () async => throw Exception('no'),
        distributorBatteryRestricted: () async => true,
        capabilities: androidCapabilities,
      ),
      isFalse,
    );
  });

  group('on a platform without a battery exemption', () {
    final noExemption = capabilitiesLike(
      androidCapabilities,
      batteryExemption: false,
    );

    test('no method needs the step, even one that would elsewhere', () async {
      for (final mode in NotificationDeliveryMode.values) {
        expect(
          await needs(
            mode,
            zunoExempt: false,
            distributorRestricted: true,
            capabilities: noExemption,
          ),
          isFalse,
          reason: mode.name,
        );
      }
    });

    test('the phone is never asked', () async {
      var asked = false;
      await needsBatteryExemptionFor(
        NotificationDeliveryMode.unifiedPush,
        zunoIgnoresBatteryOptimizations: () async {
          asked = true;
          return false;
        },
        distributorBatteryRestricted: () async {
          asked = true;
          return true;
        },
        capabilities: iosCapabilities,
      );

      expect(asked, isFalse);
    });
  });
}
