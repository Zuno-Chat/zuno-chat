import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/pusher_info.dart';
import 'package:zuno/features/settings/presentation/push_target_status_page.dart';

import '../../../helpers/fake_matrix.dart';

class _NoopPusherClient extends Client {
  _NoopPusherClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {}
}

PusherInfo _pusher({required String appId, required String pushkey}) =>
    PusherInfo(
      appId: appId,
      pushkey: pushkey,
      appDisplayName: 'Zuno Chat',
      deviceDisplayName: 'Zuno on Android',
      kind: 'http',
      lang: 'en',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/play_services');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'checkPlayServices' ? 'AVAILABLE' : null,
    );
    fcmDeliveryProvider
      ..tokenReader = (() async => 'fcm-token-abc')
      ..tokenDeleter = (() async {});
    await fcmDeliveryProvider.registerNow(_NoopPusherClient());
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await fcmDeliveryProvider.stop(_NoopPusherClient());
    unifiedPushDeliveryProvider.lastPusherError = null;
  });

  test('in fcm mode this session is identified by its registration token',
      () {
    expect(
      currentPushkeyFor(NotificationDeliveryMode.fcm),
      'fcm-token-abc',
    );
  });

  test("this session's own FCM pusher is never an \"other push target\"",
      () {
    final groups = groupPushers(
      [
        _pusher(appId: fcmAppId, pushkey: 'fcm-token-abc'),
        _pusher(appId: 'org.example.other', pushkey: 'someone-else'),
      ],
      currentPushkeyFor(NotificationDeliveryMode.fcm),
    );

    expect(groups.currentSession?.pushkey, 'fcm-token-abc');
    expect(groups.others.single.pushkey, 'someone-else');
  });

  test('a transport with nothing registered claims no pusher as its own',
      () {
    expect(
      currentPushkeyFor(NotificationDeliveryMode.backgroundService),
      isNull,
    );
    final groups = groupPushers(
      [_pusher(appId: fcmAppId, pushkey: 'fcm-token-abc')],
      currentPushkeyFor(NotificationDeliveryMode.backgroundService),
    );
    expect(groups.currentSession, isNull);
  });

  test('the last error shown is the running transport, not the other one',
      () {
    unifiedPushDeliveryProvider.lastPusherError = 'ntfy refused the endpoint';

    expect(lastPusherErrorFor(NotificationDeliveryMode.fcm), isNull);
    expect(
      lastPusherErrorFor(NotificationDeliveryMode.unifiedPush),
      'ntfy refused the endpoint',
    );
  });
}
