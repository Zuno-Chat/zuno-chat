import 'package:matrix/matrix.dart';

const fcmAppId = 'im.zuno.chat.android';

Pusher buildFcmPusher({
  required String token,
  required Uri gatewayUrl,
  required String deviceDisplayName,
}) {
  return Pusher(
    appId: fcmAppId,
    pushkey: token,
    appDisplayName: 'Zuno',
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
    data: PusherData(url: gatewayUrl, format: 'event_id_only'),
  );
}

PusherId fcmPusherId(String token) => PusherId(appId: fcmAppId, pushkey: token);
