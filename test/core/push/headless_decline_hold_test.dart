import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/push/headless_decline_hold.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/hybrid_fake_async.dart';

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

  tearDown(NotificationSoundPlayer.instance.stopIncomingRing);

  test(
    'returns immediately when another isolate already holds the port',
    () async {
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
      expect(
        CallNotificationService.instance.claimDeclinePortIfUnclaimed(),
        isTrue,
      );
      final runner = HeadlessPushRunner();

      final stopwatch = Stopwatch()..start();
      await awaitHeadlessDecline(runner).timeout(const Duration(seconds: 2));
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    },
  );

  test(
    'keeps waiting while the ring is up, then ends once it is taken down',
    () async {
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
      await const AndroidIncomingCallPresenter().showIncoming(
        callerName: 'Bob',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: 'call1',
      );
      notifications.active = [ringNotificationOnScreen()];
      final runner = HeadlessPushRunner();
      final time = FakeAsync();

      var completed = false;
      time.run((_) {
        awaitHeadlessDecline(runner).whenComplete(() => completed = true);
      });

      await time.advance(const Duration(seconds: 10));
      expect(
        completed,
        isFalse,
        reason: 'the hold ended while the ring notification was still up',
      );

      notifications.active = const [];
      await time.advance(const Duration(seconds: 1));
      expect(completed, isTrue);
    },
  );

  group('once Decline is tapped', () {
    late RecordedCallStyleCalls callStyle;

    setUp(() async {
      callStyle = installFakeCallStyleChannel();
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    Future<void> ringFor(String callId) async {
      await const AndroidIncomingCallPresenter().showIncoming(
        callerName: 'Bob',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: callId,
      );
      notifications.active = [ringNotificationOnScreen()];
    }

    Future<void> declineWhileHolding(
      String callId, {
      Future<void> Function()? meanwhile,
    }) async {
      final hold = awaitHeadlessDecline(HeadlessPushRunner());
      await meanwhile?.call();
      CallNotificationService.instance.onHeadlessDeclineForTest(
        HeadlessCallDecline(roomId: '!room:example.org', callId: callId),
      );
      await hold.timeout(const Duration(seconds: 3));
    }

    Future<String?> rememberedCallId() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return readRingingCall(prefs)?.callId;
    }

    test('takes the declined call\'s ring down', () async {
      await ringFor('call1');

      await declineWhileHolding('call1');

      expect(
        callStyle.calls.map((c) => c.method),
        contains('cancelIncomingCallStyle'),
      );
      expect(await rememberedCallId(), isNull);
    });

    test('leaves ringing a newer call that arrived while the decline was on '
        'its way', () async {
      await ringFor('call1');

      await declineWhileHolding(
        'call1',
        meanwhile: () async {
          await ringFor('call2');
          callStyle.clear();
        },
      );

      expect(
        callStyle.calls.map((c) => c.method),
        isNot(contains('cancelIncomingCallStyle')),
      );
      expect(await rememberedCallId(), 'call2');
    });
  });

  test('opens no client unless Decline is actually tapped', () async {
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        throw StateError('should not be reached');
      };
    final time = FakeAsync();

    var completed = false;
    time.run((_) {
      awaitHeadlessDecline(runner).whenComplete(() => completed = true);
    });
    await time.advance(const Duration(seconds: 1));

    expect(completed, isTrue);
    expect(builds, 0);
  });
}
