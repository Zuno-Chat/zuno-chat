import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/pusher_format.dart';
import 'package:zuno/core/push/pusher_info.dart';

const _gatewayAddress = 'https://matrix.example.org/_matrix/push/v1/notify';
const _oldAddress = 'https://old.example.org/_matrix/push/v1/notify';
final _gateway = Uri.parse(_gatewayAddress);

PusherInfo _pusher({
  String? url = _gatewayAddress,
  String? format = 'event_id_only',
}) => PusherInfo(
  appId: 'im.zuno.chat.ios',
  pushkey: 'obLD1A==',
  appDisplayName: 'Zuno',
  deviceDisplayName: 'Zuno on iOS',
  kind: 'http',
  lang: 'en',
  url: url,
  format: format,
);

void main() {
  group('pusherFit', () {
    test('this server\'s address, in any letter case or with its default '
        'port, sending event ids fits', () {
      for (final url in [
        _gatewayAddress,
        'https://Matrix.Example.org:443/_matrix/push/v1/notify',
      ]) {
        expect(pusherFit(_pusher(url: url), gatewayUrl: _gateway), (
          gateway: true,
          format: true,
        ), reason: url);
      }
    });

    test('another address misses the gateway, not the format', () {
      for (final url in [
        _oldAddress,
        'https://matrix.example.org:8448/_matrix/push/v1/notify',
        'http://matrix.example.org/_matrix/push/v1/notify',
        '',
        null,
      ]) {
        expect(pusherFit(_pusher(url: url), gatewayUrl: _gateway), (
          gateway: false,
          format: true,
        ), reason: url);
      }
    });

    test('asking for full events misses the format, not the gateway', () {
      for (final format in ['full', null]) {
        expect(pusherFit(_pusher(format: format), gatewayUrl: _gateway), (
          gateway: true,
          format: false,
        ), reason: format);
      }
    });

    test('without a known server any address fits', () {
      expect(pusherFit(_pusher(url: _oldAddress), gatewayUrl: null), (
        gateway: true,
        format: true,
      ));
    });
  });
}
