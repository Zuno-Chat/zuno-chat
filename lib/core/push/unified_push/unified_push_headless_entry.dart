import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' show Client;

import '../../errors/crash_reporting.dart';
import '../../matrix/client_lease.dart';
import '../handling/headless_decline_hold.dart';
import '../handling/headless_push_runner.dart';
import '../handling/push_wake_lock.dart';
import 'unified_push_delivery_provider.dart';

const unifiedPushClientIdleLimit = Duration(minutes: 10);

Future<void> runUnifiedPushHeadless({
  required Future<Client> Function() clientBuilder,
  UnifiedPushDeliveryProvider? provider,
  Future<void> Function() initCrashReporting = initHeadlessCrashReporting,
  Future<void> Function() initializeNotifications =
      initializeHeadlessNotifications,
  Future<void> Function(HeadlessPushRunner runner) hold = awaitHeadlessDecline,
  PushWakeLockRelease releaseWakeLock = releasePushWakeLock,
  Duration firstCallbackTimeout = const Duration(seconds: 20),
  Stream<void>? yieldRequests,
}) async {
  startHeadlessCrashReporting(initCrashReporting);
  debugPrint('zuno/push: headless push handler starting');
  final delivery = provider ?? unifiedPushDeliveryProvider;
  delivery.runner
    ..idleLimit = unifiedPushClientIdleLimit
    ..yieldWhenAsked(yieldRequests ?? ClientLeases.instance.yieldRequests);
  holdRingsUntilDeclined(delivery.runner, hold: hold);
  answerQuiescence(delivery.runner);
  await delivery.ensureHeadlessCallbacksRegistered(
    clientBuilder: clientBuilder,
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
