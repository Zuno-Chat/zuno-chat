import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/apns_pusher_check.dart';
import 'package:zuno/core/push/pusher_info.dart';

const _appId = 'im.zuno.chat.ios';
const _pushkey = 'obLD1A==';
const _oldAddress = 'https://old.example.org/_matrix/push/v1/notify';
final _gateway = Uri.parse('https://matrix.example.org/_matrix/push/v1/notify');

PusherInfo _pusher({
  String appId = _appId,
  String pushkey = _pushkey,
  String? url = 'https://matrix.example.org/_matrix/push/v1/notify',
  String? format = 'event_id_only',
}) => PusherInfo(
  appId: appId,
  pushkey: pushkey,
  appDisplayName: 'Zuno',
  deviceDisplayName: 'Zuno on iOS',
  kind: 'http',
  lang: 'en',
  url: url,
  format: format,
);

ApnsPusherCheck _check(List<PusherInfo>? pushers) => checkApnsPusher(
  pushers,
  appId: _appId,
  pushkey: _pushkey,
  gatewayUrl: _gateway,
);

void main() {
  group('checkApnsPusher', () {
    test('this device sending event ids to this server matches', () {
      expect(_check([_pusher()]), ApnsPusherCheck.matches);
    });

    test('no pusher with this app id and push key is missing', () {
      expect(_check([]), ApnsPusherCheck.missing);
      expect(
        _check([
          _pusher(appId: 'im.zuno.chat.ios.dev'),
          _pusher(pushkey: 'other'),
        ]),
        ApnsPusherCheck.missing,
      );
    });

    test('a pusher that misses the gateway or the format is outdated', () {
      expect(_check([_pusher(url: _oldAddress)]), ApnsPusherCheck.outdated);
      expect(_check([_pusher(format: 'full')]), ApnsPusherCheck.outdated);
    });

    test('a pusher list that could not be read is unknown', () {
      expect(_check(null), ApnsPusherCheck.unknown);
    });
  });
}
