import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart' show Client;

import '../notifications/notification_delivery_provider.dart';
import '../notifications/unified_push_delivery_provider.dart';
import 'headless_decline_hold.dart';
import 'headless_push_runner.dart';
import 'incoming_push_handler.dart';
import 'push_wake_lock.dart';

Future<void> runUnifiedPushHeadless({
  required Future<Client> Function() clientBuilder,
  UnifiedPushDeliveryProvider? provider,
  Future<void> Function() initializeNotifications =
      initializeHeadlessNotifications,
  Future<void> Function(HeadlessPushRunner runner) hold = awaitHeadlessDecline,
  Future<void> Function() releaseWakeLock = releasePushWakeLock,
  Duration firstCallbackTimeout = const Duration(seconds: 20),
}) async {
  debugPrint('zuno/push: headless push handler starting');
  final delivery = provider ?? unifiedPushDeliveryProvider;
  await delivery.ensureHeadlessCallbacksRegistered(
    clientBuilder: clientBuilder,
    onPushHandled: (outcome) async {
      debugPrint('zuno/push: headless callback done, outcome=$outcome');
      try {
        if (outcome == IncomingPushOutcome.callRinging) {
          await hold(delivery.runner);
        }
      } finally {
        await releaseWakeLock();
      }
    },
  );
  await prepareHeadlessPush(
    delivery.runner,
    initializeNotifications: initializeNotifications,
  );
  await delivery.waitForFirstCallback(timeout: firstCallbackTimeout);
  debugPrint('zuno/push: headless handler idle');
}
