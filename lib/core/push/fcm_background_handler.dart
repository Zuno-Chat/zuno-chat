import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:matrix/matrix.dart' show Client;

import '../errors/crash_reporting.dart';
import '../matrix/matrix_client_provider.dart';
import '../notifications/fcm_delivery_provider.dart';
import 'fcm_push_notification.dart';
import 'headless_decline_hold.dart';
import 'headless_push_runner.dart';
import 'incoming_push_handler.dart';

Future<void> handleFcmMessage(
  HeadlessPushRunner runner,
  Map<String, dynamic> data,
) async {
  final notification = pushNotificationFromFcmData(data);
  if (notification == null) {
    debugPrint('zuno/push: FCM payload could not be decoded');
    return;
  }
  await runner.deliver(notification);
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
}) {
  late final HeadlessPushRunner runner;
  runner = HeadlessPushRunner()
    ..clientBuilder = clientBuilder
    ..onPushHandled = (outcome) async {
      if (outcome != IncomingPushOutcome.callRinging) return;
      unawaited(_holdWhileRinging(runner, hold));
    };
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

@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHeadlessCrashReporting();
  final runner = fcmBackgroundRunner();
  if (!await prepareHeadlessPush(runner)) return;
  await handleFcmMessage(runner, message.data);
}

bool _foregroundListenerAttached = false;

@visibleForTesting
Stream<RemoteMessage> Function() foregroundFcmMessages = () =>
    FirebaseMessaging.onMessage;

void listenForForegroundFcmMessages() {
  if (_foregroundListenerAttached) return;
  _foregroundListenerAttached = true;
  foregroundFcmMessages().listen((message) {
    handleFcmMessage(fcmDeliveryProvider.runner, message.data);
  });
}

@visibleForTesting
void resetForegroundFcmListenerForTesting() =>
    _foregroundListenerAttached = false;
