import 'package:matrix/matrix.dart';

const apnsAppId = 'im.zuno.chat.ios';

Pusher buildApnsPusher({
  required String token,
  required Uri gatewayUrl,
  required String deviceDisplayName,
}) {
  return Pusher(
    appId: apnsAppId,
    pushkey: token,
    appDisplayName: 'Zuno',
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
    data: PusherData(
      url: gatewayUrl,
      format: 'event_id_only',
      additionalProperties: const {
        'default_payload': {
          'aps': {
            'mutable-content': 1,
            'alert': {'body': 'New message'},
            'sound': 'default',
          },
        },
      },
    ),
  );
}

PusherId apnsPusherId(String token) =>
    PusherId(appId: apnsAppId, pushkey: token);
