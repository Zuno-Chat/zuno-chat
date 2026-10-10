import 'package:matrix/matrix.dart';
import 'package:unifiedpush_platform_interface/data/public_key_set.dart';

import 'pusher_format.dart';

const unifiedPushAppId = 'im.zuno.chat.unifiedpush';

bool unifiedPushViaHomeserverGateway = false;

Pusher buildUnifiedPushPusher({
  required Uri endpointUrl,
  required Uri gatewayUrl,
  required String deviceDisplayName,
}) {
  return Pusher(
    appId: unifiedPushAppId,
    pushkey: endpointUrl.toString(),
    appDisplayName: 'Zuno',
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
    data: PusherData(url: gatewayUrl, format: pusherFormat),
  );
}

Pusher buildUnifiedPushWebPusher({
  required Uri endpointUrl,
  required PublicKeySet keys,
  required Uri gatewayUrl,
  required String deviceDisplayName,
}) {
  return Pusher(
    appId: unifiedPushAppId,
    pushkey: keys.pubKey,
    appDisplayName: 'Zuno',
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
    data: PusherData(
      url: gatewayUrl,
      format: pusherFormat,
      additionalProperties: {
        'endpoint': endpointUrl.toString(),
        'auth': keys.auth,
      },
    ),
  );
}

PusherId unifiedPushPusherIdFor(String pushkey) =>
    PusherId(appId: unifiedPushAppId, pushkey: pushkey);
