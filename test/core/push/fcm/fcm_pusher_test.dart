import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm/fcm_pusher.dart';
import 'package:zuno/core/push/pushers/push_gateway.dart';

void main() {
  const token = 'fZx9Q:APA91bHun4MxP5egoKMwt2K';

  test('builds a Pusher with the FCM token as pushkey', () {
    final pusher = buildFcmPusher(
      token: token,
      deviceDisplayName: 'Zuno on Android',
    );
    expect(pusher.appId, 'im.zuno.chat.android');
    expect(pusher.pushkey, token);
    expect(pusher.appDisplayName, 'Zuno');
    expect(pusher.deviceDisplayName, 'Zuno on Android');
    expect(pusher.kind, 'http');
    expect(pusher.lang, 'en');
    expect(pusher.data.url, zunoPushGateway);
    expect(pusher.data.format, 'event_id_only');
  });

  test('fcmPusherId matches buildFcmPusher\'s own id fields', () {
    final pusher = buildFcmPusher(
      token: token,
      deviceDisplayName: 'Zuno on Android',
    );
    final id = fcmPusherId(token);
    expect(id.appId, pusher.appId);
    expect(id.pushkey, pusher.pushkey);
  });
}
