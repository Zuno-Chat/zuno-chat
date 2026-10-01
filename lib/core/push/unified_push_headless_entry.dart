import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' show Client;

import '../matrix/client_lease.dart';
import '../notifications/notification_delivery_provider.dart';
import '../notifications/unified_push_delivery_provider.dart';
import 'headless_decline_hold.dart';
import 'headless_push_runner.dart';
import 'incoming_push_handler.dart';
import 'push_wake_lock.dart';

const unifiedPushClientIdleLimit = Duration(minutes: 10);

Future<void> runUnifiedPushHeadless({
  required Future<Client> Function() clientBuilder,
  UnifiedPushDeliveryProvider? provider,
  Future<void> Function() initializeNotifications =
      initializeHeadlessNotifications,
  Future<void> Function(HeadlessPushRunner runner) hold = awaitHeadlessDecline,
  PushWakeLockRelease releaseWakeLock = releasePushWakeLock,
  Duration firstCallbackTimeout = const Duration(seconds: 20),
  Stream<void>? yieldRequests,
}) async {
  debugPrint('zuno/push: headless push handler starting');
  final delivery = provider ?? unifiedPushDeliveryProvider;
  delivery.runner
    ..idleLimit = unifiedPushClientIdleLimit
    ..yieldWhenAsked(yieldRequests ?? ClientLeases.instance.yieldRequests);
  answerQuiescence(delivery.runner);
  await delivery.ensureHeadlessCallbacksRegistered(
    clientBuilder: clientBuilder,
    onPushHandled: (outcome) async {
      debugPrint('zuno/push: headless callback done, outcome=$outcome');
      if (outcome == IncomingPushOutcome.callRinging) {
        await hold(delivery.runner);
      }
    },
    releaseAfterPush: releaseWakeLock,
  );
  await prepareHeadlessPush(initializeNotifications: initializeNotifications);
  await delivery.waitForFirstCallback(timeout: firstCallbackTimeout);
  debugPrint('zuno/push: headless handler idle');
}

void answerQuiescence(
  HeadlessPushRunner runner, {
  MethodChannel channel = const MethodChannel('zuno/push_wakelock'),
}) {
  channel.setMethodCallHandler((call) async {
    if (call.method == 'quiescent') return runner.settle();
    throw MissingPluginException('zuno/push_wakelock has no ${call.method}');
  });
}
