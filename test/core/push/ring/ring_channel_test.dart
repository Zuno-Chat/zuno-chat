import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/fcm/fcm_pusher.dart';
import 'package:zuno/core/push/ring/ring_channel.dart';

import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Map<String, Object?> replies;

  void answer(MethodChannel channel) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final reply = replies[call.method];
      if (reply is PlatformException) throw reply;
      return reply;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  setUp(() {
    calls = [];
    replies = {};
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
  });

  group('the VoIP channel', () {
    setUp(() => answer(ringChannel));

    test('reads the token, environment, key and CallKit support', () async {
      replies['status'] = {
        'token': 'dG9rZW4=',
        'environment': 'development',
        'kid': 16909060,
        'key': 'a2V5',
        'rings': true,
      };

      final status = await const RingChannel().status();

      expect(status, (
        token: 'dG9rZW4=',
        environment: 'development',
        appId: voipDevelopmentAppId,
        kid: 16909060,
        key: 'a2V5',
        canRing: true,
      ));
    });

    test('reports no token until PushKit has given one', () async {
      replies['status'] = {
        'token': null,
        'environment': 'production',
        'kid': 7,
        'key': 'a2V5',
        'rings': false,
      };

      final status = await const RingChannel().status();

      expect(status?.token, isNull);
      expect(status?.canRing, isFalse);
    });

    test('a status without its key is no status at all', () async {
      replies['status'] = {'environment': 'production', 'kid': 7};

      expect(await const RingChannel().status(), isNull);
    });

    test(
      'passes a rotation, an acknowledgement and the session through',
      () async {
        replies['rotateKey'] = {'kid': 9, 'key': 'bmV3'};

        final rotated = await const RingChannel().rotateKey();
        await const RingChannel().ackKey(9, serverOffsetMs: -250);
        await const RingChannel().setSession(signedIn: false);
        await const RingChannel().setSession(
          signedIn: true,
          userId: '@me:zuno.im',
        );

        expect(rotated, (kid: 9, key: 'bmV3'));
        expect(calls.map((c) => [c.method, c.arguments]), [
          ['rotateKey', null],
          [
            'ackKey',
            {'kid': 9, 'serverOffsetMs': -250},
          ],
          [
            'setSession',
            {'signedIn': false},
          ],
          [
            'setSession',
            {'signedIn': true, 'userId': '@me:zuno.im'},
          ],
        ]);
      },
    );

    test('takes the events it knows and skips the rest', () async {
      replies['takeEvents'] = [
        {'type': 'token'},
        {'type': 'somethingNew'},
        'not an event',
        {'type': 'keyMismatch'},
        {'type': 'invalidated'},
      ];

      expect(await const RingChannel().takeEvents(), [
        RingRegistrationEvent.token,
        RingRegistrationEvent.keyMismatch,
        RingRegistrationEvent.invalidated,
      ]);
    });

    test('exports the test values only from a development build', () async {
      replies['devExport'] = {
        'token': 'abcd',
        'kid': 3,
        'key': 'a2V5',
        'environment': 'development',
      };

      expect(await const RingChannel().devExport(), (
        token: 'abcd',
        kid: 3,
        key: 'a2V5',
      ));
    });

    test('never exports test values that claim another environment', () async {
      replies['devExport'] = {
        'token': 'abcd',
        'kid': 3,
        'key': 'a2V5',
        'environment': 'production',
      };

      expect(await const RingChannel().devExport(), isNull);
    });

    test('a refusal from native code reads as nothing', () async {
      replies['status'] = PlatformException(code: 'keychain');

      expect(await const RingChannel().status(), isNull);
    });

    test('on Android the ring registration reaches native code, under the FCM '
        'app id', () async {
      ambientCapabilities = androidCapabilities;
      replies['status'] = {
        'token': 'ZmNt',
        'environment': 'production',
        'kid': 7,
        'key': 'a2V5',
        'rings': true,
      };

      final status = await const RingChannel().status();

      expect(status?.appId, fcmAppId);
      expect(status?.token, 'ZmNt');
    });
  });

  test('without the plugin every call is a quiet no-op', () async {
    messenger.setMockMethodCallHandler(ringChannel, null);

    expect(await const RingChannel().status(), isNull);
    expect(await const RingChannel().takeEvents(), isEmpty);
  });
}
