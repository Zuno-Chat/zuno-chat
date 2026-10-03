import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/apns_pusher_check.dart';
import 'package:zuno/core/push/pusher_info.dart';

const _appId = 'im.zuno.chat.ios';
const _pushkey = 'obLD1A==';
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
  test('this device sending event ids to this server matches', () {
    expect(_check([_pusher()]), ApnsPusherCheck.matches);
  });

  test('the same address in another case or with the default port still '
      'matches', () {
    expect(
      _check([
        _pusher(url: 'https://Matrix.Example.org:443/_matrix/push/v1/notify'),
      ]),
      ApnsPusherCheck.matches,
    );
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

  test('a pusher sending to another address is outdated', () {
    for (final url in [
      'https://old.example.org/_matrix/push/v1/notify',
      'https://matrix.example.org:8448/_matrix/push/v1/notify',
      'http://matrix.example.org/_matrix/push/v1/notify',
      '',
      null,
    ]) {
      expect(
        _check([_pusher(url: url)]),
        ApnsPusherCheck.outdated,
        reason: url,
      );
    }
  });

  test('a pusher asking for full events is outdated', () {
    for (final format in ['full', null]) {
      expect(
        _check([_pusher(format: format)]),
        ApnsPusherCheck.outdated,
        reason: format,
      );
    }
  });

  test('without a known server only the format is checked', () {
    expect(
      checkApnsPusher(
        [_pusher(url: 'https://old.example.org/_matrix/push/v1/notify')],
        appId: _appId,
        pushkey: _pushkey,
        gatewayUrl: null,
      ),
      ApnsPusherCheck.matches,
    );
    expect(
      checkApnsPusher(
        [_pusher(format: 'full')],
        appId: _appId,
        pushkey: _pushkey,
        gatewayUrl: null,
      ),
      ApnsPusherCheck.outdated,
    );
  });

  test('a pusher list that could not be read is unknown', () {
    expect(_check(null), ApnsPusherCheck.unknown);
  });
}
