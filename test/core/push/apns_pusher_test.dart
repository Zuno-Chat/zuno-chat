import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/apns_pusher.dart';

void main() {
  group('apnsPushkeyFromToken', () {
    test('encodes the token bytes as base64, the form the gateway decodes by '
        'default', () {
      expect(apnsPushkeyFromToken('a1b2c3d4'), 'obLD1A==');
      expect(apnsPushkeyFromToken('A1B2C3D4'), 'obLD1A==');
    });

    test('a full token round-trips to its 32 bytes and is never the hex '
        'itself', () {
      final token = 'a1b2c3d4' * 8;

      final pushkey = apnsPushkeyFromToken(token)!;

      expect(pushkey, isNot(token));
      expect(base64Decode(pushkey), hasLength(32));
      expect(base64Decode(pushkey).take(4), [0xa1, 0xb2, 0xc3, 0xd4]);
    });

    test('refuses anything that is not hex', () {
      for (final bad in ['', 'abc', 'apns-token', 'zz', 'a1b2 c3d4']) {
        expect(apnsPushkeyFromToken(bad), isNull, reason: '"$bad"');
      }
    });
  });

  test('a release build registers under the production app id, any other '
      'build under the development one', () {
    expect(apnsAppIdFor(release: true), 'im.zuno.chat.ios');
    expect(apnsAppIdFor(release: false), 'im.zuno.chat.ios.dev');
  });
}
