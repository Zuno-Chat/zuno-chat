import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const callsChannel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CallNotificationService service;

  Future<void> fromNative(String method, Object? arguments) =>
      messenger.handlePlatformMessage(
        callsChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        null,
      );

  const bobsCall = {
    'roomId': '!room:example.org',
    'callId': 'call1',
    'callerId': '@bob:example.org',
    'isVideo': true,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    service = CallNotificationService(capabilities: iosCapabilities);
    await service.initialize(claimDeclinePort: false);
  });

  test('an answer from the system call screen reaches whoever handles call '
      'actions', () async {
    final action = service.onAction.first;

    await fromNative('answerCall', bobsCall);

    final response = await action.timeout(const Duration(seconds: 2));
    expect(response.action, CallNotificationAction.accept);
    expect(response.call, (
      roomId: '!room:example.org',
      callId: 'call1',
      callerId: '@bob:example.org',
      isVideo: true,
    ));
  });

  test('a decline from the system call screen does too', () async {
    final action = service.onAction.first;

    await fromNative('declineCall', bobsCall);

    expect(
      (await action.timeout(const Duration(seconds: 2))).action,
      CallNotificationAction.decline,
    );
  });

  test('an action that arrives before anything listens, as on a cold start '
      'from the lock screen, is kept for the launch check, once', () async {
    await fromNative('answerCall', bobsCall);

    final launch = await service.takeLaunchCallActionFromNotification();
    expect(launch?.action, CallNotificationAction.accept);
    expect(launch?.call.callId, 'call1');
    expect(await service.takeLaunchCallActionFromNotification(), isNull);
  });

  test('an action with no call to name is dropped', () async {
    final seen = <CallNotificationResponse>[];
    final sub = service.onAction.listen(seen.add);
    addTearDown(sub.cancel);

    await fromNative('answerCall', {'roomId': '!room:example.org'});
    await fromNative('answerCall', null);

    expect(seen, isEmpty);
    expect(await service.takeLaunchCallActionFromNotification(), isNull);
  });
}
