import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/push/headless_decline_hold.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../helpers/fake_local_notifications.dart';

const _ringNotificationId = 4002;

Map<String, Object?> _ringOnScreen() => {
  'id': _ringNotificationId,
  'channelId': 'calls_ringing',
  'groupKey': null,
  'tag': null,
  'title': 'Incoming voice call',
  'body': 'Bob',
  'payload': null,
  'bigText': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordedNotifications notifications;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
  });

  tearDown(() {
    CallNotificationService.instance.releaseDeclinePort();
  });

  test('returns immediately when another isolate already holds the port',
      () async {
    await CallNotificationService.instance.initialize();
    final runner = HeadlessPushRunner();

    final stopwatch = Stopwatch()..start();
    await awaitHeadlessDecline(runner).timeout(const Duration(seconds: 2));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('keeps waiting while the ring is up, then ends once it is taken down',
      () async {
    await CallNotificationService.instance.initialize(
      claimDeclinePort: false,
    );
    await CallNotificationService.instance.showIncomingCall(
      callerName: 'Bob',
      callerId: '@bob:example.org',
      isVideo: false,
      roomId: '!room:example.org',
      callId: 'call1',
    );
    notifications.active = [_ringOnScreen()];
    final runner = HeadlessPushRunner();

    var completed = false;
    final future = awaitHeadlessDecline(
      runner,
    ).whenComplete(() => completed = true);

    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(
      completed,
      isFalse,
      reason: 'the hold ended while the ring notification was still up',
    );

    notifications.active = const [];
    await future.timeout(const Duration(seconds: 3));
    expect(completed, isTrue);
  });

  test('opens no client unless Decline is actually tapped', () async {
    await CallNotificationService.instance.initialize(
      claimDeclinePort: false,
    );
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        throw StateError('should not be reached');
      };

    await awaitHeadlessDecline(runner).timeout(const Duration(seconds: 5));

    expect(builds, 0);
  });
}
