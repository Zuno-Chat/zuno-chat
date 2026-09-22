import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/pusher_info.dart';
import 'package:zuno/core/push/unified_push_pusher.dart';

Map<String, Object?> _pusherJson({
  String appId = unifiedPushAppId,
  String pushkey = 'https://ntfy.sh/upABC',
}) => {
  'app_id': appId,
  'pushkey': pushkey,
  'app_display_name': 'Zuno Chat',
  'device_display_name': 'Zuno on Android',
  'kind': 'http',
  'lang': 'en',
  'profile_tag': 'xyz',
  'device_id': 'ABCDEF',
  'data': {
    'url': 'https://ntfy.sh/_matrix/push/v1/notify',
    'format': 'event_id_only',
  },
};

void main() {
  group('PusherInfo.fromJson', () {
    test('reads every field the homeserver sent, MSC3881 ones included', () {
      final pusher = PusherInfo.fromJson(_pusherJson());

      expect(pusher.appId, unifiedPushAppId);
      expect(pusher.pushkey, 'https://ntfy.sh/upABC');
      expect(pusher.appDisplayName, 'Zuno Chat');
      expect(pusher.deviceDisplayName, 'Zuno on Android');
      expect(pusher.kind, 'http');
      expect(pusher.lang, 'en');
      expect(pusher.profileTag, 'xyz');
      expect(pusher.url, 'https://ntfy.sh/_matrix/push/v1/notify');
      expect(pusher.format, 'event_id_only');
      expect(pusher.deviceId, 'ABCDEF');
    });

    test('leaves the optional MSC3881 fields null when absent', () {
      final json = _pusherJson()
        ..remove('profile_tag')
        ..remove('device_id');

      final pusher = PusherInfo.fromJson(json);

      expect(pusher.profileTag, isNull);
      expect(pusher.deviceId, isNull);
    });

    test('survives missing and wrong-typed fields instead of throwing', () {
      final pusher = PusherInfo.fromJson({
        'app_id': 42,
        'pushkey': null,
        'data': 'not-an-object',
      });

      expect(pusher.appId, '');
      expect(pusher.pushkey, '');
      expect(pusher.url, isNull);
      expect(pusher.format, isNull);
    });
  });

  group('groupPushers', () {
    final endpoint = Uri.parse('https://ntfy.sh/upABC');

    test('picks out this session and leaves everything else in one list', () {
      final mine = PusherInfo.fromJson(_pusherJson());
      final otherDevice = PusherInfo.fromJson(
        _pusherJson(pushkey: 'https://ntfy.sh/upOTHER'),
      );
      final otherApp = PusherInfo.fromJson(
        _pusherJson(appId: 'im.fluffychat', pushkey: 'https://ntfy.sh/upFC'),
      );

      final groups = groupPushers([
        otherApp,
        mine,
        otherDevice,
      ], endpoint.toString());

      expect(groups.currentSession?.pushkey, mine.pushkey);
      expect(groups.others.map((p) => p.pushkey), [
        otherApp.pushkey,
        otherDevice.pushkey,
      ]);
    });

    test('the order the homeserver sent is kept', () {
      final first = PusherInfo.fromJson(
        _pusherJson(appId: 'im.fluffychat', pushkey: 'https://ntfy.sh/up1'),
      );
      final second = PusherInfo.fromJson(
        _pusherJson(pushkey: 'https://ntfy.sh/up2'),
      );
      final third = PusherInfo.fromJson(
        _pusherJson(appId: 'org.example', pushkey: 'https://ntfy.sh/up3'),
      );

      final groups = groupPushers([first, second, third], endpoint.toString());

      expect(groups.others.map((p) => p.pushkey), [
        first.pushkey,
        second.pushkey,
        third.pushkey,
      ]);
    });

    test('this session is matched on app id as well as pushkey', () {
      final impostor = PusherInfo.fromJson(
        _pusherJson(appId: 'im.fluffychat', pushkey: endpoint.toString()),
      );

      final groups = groupPushers([impostor], endpoint.toString());

      expect(groups.currentSession, isNull);
      expect(groups.others, hasLength(1));
    });

    test(
      'with no endpoint yet, this app\'s pushers are just other pushers',
      () {
        final mine = PusherInfo.fromJson(_pusherJson());

        final groups = groupPushers([mine], null);

        expect(groups.currentSession, isNull);
        expect(groups.others, hasLength(1));
      },
    );

    test('an empty list groups to nothing at all', () {
      final groups = groupPushers(const [], endpoint.toString());

      expect(groups.currentSession, isNull);
      expect(groups.others, isEmpty);
    });

    test('picks out this session\'s FCM pusher among other devices\'', () {
      const token = 'fZx9Q:APA91bHun4MxP5egoKMwt2K';
      final groups = groupPushers([
        PusherInfo.fromJson({
          'app_id': 'im.zuno.chat.unifiedpush',
          'pushkey': 'https://ntfy.sh/upOther',
          'app_display_name': 'Zuno Chat',
          'device_display_name': 'Another phone',
          'kind': 'http',
          'lang': 'en',
        }),
        PusherInfo.fromJson({
          'app_id': 'im.zuno.chat.android',
          'pushkey': token,
          'app_display_name': 'Zuno Chat',
          'device_display_name': 'This device',
          'kind': 'http',
          'lang': 'en',
        }),
      ], token);

      expect(groups.currentSession?.deviceDisplayName, 'This device');
      expect(groups.others, hasLength(1));
      expect(groups.others.single.appId, 'im.zuno.chat.unifiedpush');
    });

    test('another app sharing our pushkey is not this session', () {
      const token = 'fZx9Q:APA91bHun4MxP5egoKMwt2K';
      final groups = groupPushers([
        PusherInfo.fromJson({
          'app_id': 'org.example.other',
          'pushkey': token,
          'app_display_name': 'Something else',
          'device_display_name': 'This device',
          'kind': 'http',
          'lang': 'en',
        }),
      ], token);

      expect(groups.currentSession, isNull);
      expect(groups.others, hasLength(1));
    });
  });
}
