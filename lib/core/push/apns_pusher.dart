import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:matrix/matrix.dart';

const apnsProductionAppId = 'im.zuno.chat.ios';
const apnsDevelopmentAppId = 'im.zuno.chat.ios.dev';

const apnsPusherFormat = 'event_id_only';

enum ApnsEnvironment { production, development }

ApnsEnvironment? apnsEnvironmentNamed(Object? name) => switch (name) {
  'production' => ApnsEnvironment.production,
  'development' => ApnsEnvironment.development,
  _ => null,
};

String apnsAppIdForEnvironment(ApnsEnvironment environment) =>
    switch (environment) {
      ApnsEnvironment.production => apnsProductionAppId,
      ApnsEnvironment.development => apnsDevelopmentAppId,
    };

String apnsAppIdFor({required bool release}) =>
    release ? apnsProductionAppId : apnsDevelopmentAppId;

final apnsAppId = apnsAppIdFor(release: kReleaseMode);

final _hexToken = RegExp(r'^(?:[0-9a-fA-F]{2})+$');

String? apnsPushkeyFromToken(String token) {
  if (!_hexToken.hasMatch(token)) return null;
  final bytes = List<int>.generate(
    token.length ~/ 2,
    (i) => int.parse(token.substring(2 * i, 2 * i + 2), radix: 16),
  );
  return base64Encode(bytes);
}

Pusher buildApnsPusher({
  required String appId,
  required String pushkey,
  required Uri gatewayUrl,
  required String deviceDisplayName,
  required String? sound,
}) {
  return Pusher(
    appId: appId,
    pushkey: pushkey,
    appDisplayName: 'Zuno',
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
    data: PusherData(
      url: gatewayUrl,
      format: apnsPusherFormat,
      additionalProperties: {
        'default_payload': {
          'aps': {
            'mutable-content': 1,
            'alert': const {'body': 'New message'},
            'sound': ?sound,
          },
        },
      },
    ),
  );
}
