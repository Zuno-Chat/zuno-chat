import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/crash_reporting.dart';
import '../matrix/client_lease.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/session_display_name.dart';
import '../notifications/fcm_delivery_provider.dart' show fcmPendingTokenKey;
import '../notifications/notification_permission.dart';
import 'fcm_bridge.dart';
import 'fcm_gateway.dart';
import 'fcm_push_notification.dart';
import 'fcm_pusher.dart';
import 'fcm_registration_store.dart';
import 'headless_decline_hold.dart';
import 'headless_push_runner.dart';

Future<void> handleFcmPush(HeadlessPushRunner runner, FcmPush push) async {
  final notification = pushNotificationFromFcmData(push.data);
  if (notification == null) {
    debugPrint('zuno/push: FCM payload could not be decoded');
    return;
  }
  await runner.deliver(notification, appInFront: push.appInFront);
}

HeadlessPushRunner? _backgroundRunner;

HeadlessPushRunner fcmBackgroundRunner() =>
    _backgroundRunner ??= buildFcmBackgroundRunner(
      clientBuilder: () async {
        final result = await createMatrixClient(backgroundSync: false);
        debugPrint('zuno/push: FCM headless client ready');
        return result.client;
      },
    );

@visibleForTesting
HeadlessPushRunner buildFcmBackgroundRunner({
  required Future<Client> Function() clientBuilder,
  Future<void> Function(HeadlessPushRunner runner) hold = awaitHeadlessDecline,
  Future<void> Function(Client client) retryPendingToken = retryPendingFcmToken,
}) {
  final runner = HeadlessPushRunner()..clientBuilder = clientBuilder;
  runner.onRinging = () => _holdWhileRinging(runner, hold);
  runner.onClientOpened = (_) => unawaited(
    runner
        .withClient(retryPendingToken)
        .then<void>(
          (_) {},
          onError: (Object error) => debugPrint(
            'zuno/push: the waiting FCM token check failed ($error)',
          ),
        ),
  );
  return runner;
}

Future<void> _holdWhileRinging(
  HeadlessPushRunner runner,
  Future<void> Function(HeadlessPushRunner runner) hold,
) async {
  try {
    await hold(runner);
  } catch (error, stack) {
    debugPrint('zuno/push: ring hold failed: $error\n$stack');
  }
}

@visibleForTesting
void resetFcmBackgroundRunnerForTesting() => _backgroundRunner = null;

Future<void> runFcmHeadless({
  HeadlessPushRunner? runner,
  FcmBridge? bridge,
  Future<void> Function() initCrashReporting = initHeadlessCrashReporting,
  Future<bool> Function() prepare = prepareHeadlessPush,
  Future<void> Function(HeadlessPushRunner runner, String token) refreshToken =
      refreshFcmPusherHeadless,
  Stream<void>? yieldRequests,
}) async {
  final delivery = runner ?? fcmBackgroundRunner();
  final fcm = bridge ?? FcmBridge.instance;
  delivery.yieldWhenAsked(yieldRequests ?? ClientLeases.instance.yieldRequests);
  var crashReportingStarted = false;
  void startCrashReporting() {
    if (crashReportingStarted) return;
    crashReportingStarted = true;
    unawaited(
      Future.sync(initCrashReporting).then(
        (_) {},
        onError: (Object error) =>
            debugPrint('zuno/push: crash reporting not started: $error'),
      ),
    );
  }

  Future<bool>? preparing;
  Future<bool> prepared() => preparing ??= prepare().then(
    (ready) {
      if (!ready) preparing = null;
      return ready;
    },
    onError: (Object error) {
      debugPrint('zuno/push: headless setup failed ($error)');
      preparing = null;
      return false;
    },
  );
  var jobs = 0;
  Future<void> job(Future<void> Function() run) async {
    jobs++;
    try {
      if (await prepared()) await run();
    } finally {
      jobs--;
      startCrashReporting();
    }
  }

  fcm.serve(
    onPush: (push) {
      if (pushNotificationFromFcmData(push.data)?.eventId != null) {
        delivery.prepareClient();
      }
      return job(() => handleFcmPush(delivery, push));
    },
    onToken: (token) => job(() => refreshToken(delivery, token)),
    isQuiescent: () async => jobs == 0 && await delivery.settle() && jobs == 0,
  );
  if (!await fcm.ready()) {
    debugPrint('zuno/push: the FCM router passed this engine over');
    return;
  }
  unawaited(prepared());
  debugPrint('zuno/push: FCM push engine ready');
}

Future<void> refreshFcmPusherHeadless(
  HeadlessPushRunner runner,
  String token, {
  Future<bool> Function() notificationsAllowed = mayRegisterForNotifications,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final registered = readFcmRegistration(prefs);
  if (registered == null || registered == token) return;
  if (!await notificationsAllowed()) return;
  try {
    final moved = await runner.withClient(
      (client) => _moveFcmPusher(client, prefs, from: registered, to: token),
    );
    if (moved != null) return;
  } catch (e) {
    debugPrint('zuno/push: the FCM pusher stays on the old token for now ($e)');
  }
  await prefs.setString(fcmPendingTokenKey, token);
}

Future<void> retryPendingFcmToken(
  Client client, {
  Future<bool> Function() notificationsAllowed = mayRegisterForNotifications,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pending = prefs.getString(fcmPendingTokenKey);
    if (pending == null || pending.isEmpty) return;
    final registered = readFcmRegistration(prefs);
    if (registered == null || registered == pending) {
      await prefs.remove(fcmPendingTokenKey);
      return;
    }
    if (!await notificationsAllowed()) return;
    await _moveFcmPusher(client, prefs, from: registered, to: pending);
  } catch (e) {
    debugPrint('zuno/push: the waiting FCM token is still not registered ($e)');
  }
}

Future<bool> _moveFcmPusher(
  Client client,
  SharedPreferences prefs, {
  required String from,
  required String to,
}) async {
  final gatewayUrl = fcmGatewayUri(client.homeserver);
  if (gatewayUrl == null) return false;
  await client.postPusher(
    buildFcmPusher(
      token: to,
      gatewayUrl: gatewayUrl,
      deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
    ),
  );
  await saveFcmRegistration(prefs, token: to);
  await prefs.remove(fcmPendingTokenKey);
  try {
    await client.deletePusher(fcmPusherId(from));
  } catch (e) {
    debugPrint('zuno/push: could not remove the replaced FCM pusher ($e)');
  }
  debugPrint('zuno/push: FCM pusher moved to the new token');
  return true;
}
