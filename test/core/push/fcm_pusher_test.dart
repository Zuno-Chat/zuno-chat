import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/unified_push_pusher.dart';

void main() {
  final gateway = Uri.parse(
    'https://matrix.example.org/_matrix/push/v1/notify',
  );
  const token = 'fZx9Q:APA91bHun4MxP5egoKMwt2K';

  test('builds a Pusher with the FCM token as pushkey', () {
    final pusher = buildFcmPusher(
      token: token,
      gatewayUrl: gateway,
      deviceDisplayName: 'Zuno on Android',
    );
    expect(pusher.appId, fcmAppId);
    expect(pusher.pushkey, token);
    expect(pusher.appDisplayName, 'Zuno');
    expect(pusher.deviceDisplayName, 'Zuno on Android');
    expect(pusher.kind, 'http');
    expect(pusher.lang, 'en');
    expect(pusher.data.url, gateway);
    expect(pusher.data.format, 'event_id_only');
  });

  test('uses an app id distinct from UnifiedPush\'s', () {
    expect(fcmAppId, isNot(unifiedPushAppId));
    expect(fcmAppId, 'im.zuno.chat.android');
  });

  test('fcmPusherId matches buildFcmPusher\'s own id fields', () {
    final pusher = buildFcmPusher(
      token: token,
      gatewayUrl: gateway,
      deviceDisplayName: 'Zuno on Android',
    );
    final id = fcmPusherId(token);
    expect(id.appId, pusher.appId);
    expect(id.pushkey, pusher.pushkey);
  });

  test('a pusher id for one token does not match another token', () {
    expect(fcmPusherId(token).pushkey, isNot(fcmPusherId('other').pushkey));
  });
}
