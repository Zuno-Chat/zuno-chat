import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'canUseFullScreenIntent' ? false : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  test('android keeps the call over the lock screen and asks about '
      'full-screen ringing', () async {
    final service = CallNotificationService(capabilities: androidCapabilities);

    await service.setShowOverLockscreen(true);
    expect(await service.canUseFullScreenIntent(), isFalse);
    await service.openFullScreenIntentSettings();

    expect(calls.map((c) => [c.method, c.arguments]), [
      [
        'setShowOverLockscreen',
        {'show': true},
      ],
      ['canUseFullScreenIntent', null],
      ['openFullScreenIntentSettings', null],
    ]);
  });

  test('without a lock-screen call UI the flag is never sent', () async {
    final service = CallNotificationService(
      capabilities: capabilitiesLike(
        androidCapabilities,
        lockScreenCallUi: false,
      ),
    );

    await service.setShowOverLockscreen(true);
    await service.setShowOverLockscreen(false);

    expect(calls, isEmpty);
  });

  test('without full-screen intents ringing counts as allowed, with no '
      'setting to open', () async {
    final service = CallNotificationService(
      capabilities: capabilitiesLike(
        androidCapabilities,
        fullScreenIntent: false,
      ),
    );

    expect(await service.fullScreenIntentAllowedOrNull(), isNull);
    expect(await service.canUseFullScreenIntent(), isTrue);
    await service.openFullScreenIntentSettings();

    expect(calls, isEmpty);
  });

  test('on iOS none of it reaches the platform', () async {
    final service = CallNotificationService(capabilities: iosCapabilities);

    await service.setShowOverLockscreen(true);
    expect(await service.canUseFullScreenIntent(), isTrue);
    await service.openFullScreenIntentSettings();

    expect(calls, isEmpty);
  });

  test('on iOS it initializes without prompting: onboarding owns the '
      'notification ask', () async {
    final notifications = installFakeLocalNotifications(
      platform: TargetPlatform.iOS,
    );
    final service = CallNotificationService(capabilities: iosCapabilities);

    await service.initialize(claimDeclinePort: false);

    expect(
      notifications.initializeArguments,
      allOf(
        containsPair('requestAlertPermission', false),
        containsPair('requestSoundPermission', false),
        containsPair('requestBadgePermission', false),
      ),
    );
  });
}
