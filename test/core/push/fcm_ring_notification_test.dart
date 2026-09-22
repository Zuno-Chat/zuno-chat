import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/push/fcm_background_handler.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

class _RingingClient extends Client {
  _RingingClient() : super('test', database: FakeDatabaseApi()) {
    setUserId('@me:example.org');
  }

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    final room = buildTestRoom(this);
    return buildTestEvent(
      room,
      eventId: '\$invite',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now(),
      content: const {
        'msgtype': 'im.zuno.call_invite',
        'call_id': 'call1',
        'kind': 'voice',
        'body': 'Incoming call',
      },
    );
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordedCallStyleCalls callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ringRateLimiter.clear();
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
  });

  Future<Map<String, Object?>> ringViaFcm() async {
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async => _RingingClient();
    await handleFcmMessage(runner, {
      'event_id': '\$invite',
      'room_id': '!room:example.org',
    });
    return (callStyle.lastShow.arguments as Map).cast<String, Object?>();
  }

  test('rings via the same native CallStyle call the UnifiedPush path uses',
      () async {
    final args = await ringViaFcm();

    expect(args['roomId'], '!room:example.org');
    expect(args['callId'], 'call1');
    expect(args['isVideo'], isFalse);
  });

  test('does not fetch an avatar on the push path', () async {
    final args = await ringViaFcm();

    expect(args['avatarBytes'], isNull);
  });
}
