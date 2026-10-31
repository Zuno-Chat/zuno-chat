import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/push/delivery/notification_delivery_mode.dart';

void main() {
  test('no method shouts or uses a contraction', () {
    for (final mode in NotificationDeliveryMode.values) {
      for (final text in [
        mode.label(englishLocalizations),
        mode.description(englishLocalizations),
      ]) {
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
