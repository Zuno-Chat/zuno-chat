import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_local_notifications.dart';

const ringNotificationId = 4002;

void main() {
  late RecordedNotifications notifications;

  Map<String, Object?> onScreen(int id) => {
    'id': id,
    'channelId': 'calls_ringing',
    'groupKey': null,
    'tag': null,
    'title': 'Incoming voice call',
    'body': 'Bob',
    'payload': null,
    'bigText': null,
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
  });

  Future<void> postRing() => CallNotificationService.instance.showIncomingCall(
    callerName: 'Bob',
    callerId: '@bob:example.org',
    isVideo: false,
    roomId: '!room:example.org',
    callId: 'call1',
  );

  test('reports the ringing call while its notification is showing',
      () async {
    await postRing();
    notifications.active = [onScreen(ringNotificationId)];

    final ringing = await CallNotificationService.instance.activeRingCall();

    expect(ringing, isNotNull);
    expect(ringing!.callId, 'call1');
    expect(ringing.roomId, '!room:example.org');
    expect(ringing.callerId, '@bob:example.org');
    expect(ringing.isVideo, isFalse);
  });

  test('reports nothing once the ring notification is gone', () async {
    await postRing();
    notifications.active = const [];

    expect(await CallNotificationService.instance.activeRingCall(), isNull);
  });

  test('is not fooled by an unrelated notification being on screen',
      () async {
    await postRing();
    notifications.active = [onScreen(12345)];

    expect(await CallNotificationService.instance.activeRingCall(), isNull);
  });

  test('forgets the stored call when the ring is cancelled', () async {
    final callStyle = installFakeCallStyleChannel();
    await postRing();
    await CallNotificationService.instance.cancelIncomingCall();
    notifications.active = const [];

    expect(await CallNotificationService.instance.activeRingCall(), isNull);
    expect(
      callStyle.calls.map((c) => c.method),
      contains('cancelIncomingCallStyle'),
    );
  });
}
