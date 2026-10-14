import 'package:matrix/matrix.dart';

import '../brand.dart';
import 'pusher_format.dart';

const fcmAppId = 'im.zuno.chat.android';

Pusher buildFcmPusher({
  required String token,
  required Uri gatewayUrl,
  required String deviceDisplayName,
}) {
  return Pusher(
    appId: fcmAppId,
    pushkey: token,
    appDisplayName: zunoName,
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
    data: PusherData(url: gatewayUrl, format: pusherFormat),
  );
}

PusherId fcmPusherId(String token) => PusherId(appId: fcmAppId, pushkey: token);
