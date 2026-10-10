import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/voip/launch_channel.dart';
import 'package:zuno/core/push/voip/voip_channel.dart';

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
    setUp(() => answer(voipChannel));

    test('reads the token, environment, key and CallKit support', () async {
      replies['status'] = {
        'token': 'dG9rZW4=',
        'environment': 'development',
        'kid': 16909060,
        'key': 'a2V5',
        'callkit': true,
      };

      final status = await const VoipChannel().status();

      expect(status, (
        token: 'dG9rZW4=',
        environment: 'development',
        kid: 16909060,
        key: 'a2V5',
        callKit: true,
      ));
    });

    test('reports no token until PushKit has given one', () async {
      replies['status'] = {
        'token': null,
        'environment': 'production',
        'kid': 7,
        'key': 'a2V5',
        'callkit': false,
      };

      final status = await const VoipChannel().status();

      expect(status?.token, isNull);
      expect(status?.callKit, isFalse);
    });

    test('a status without its key is no status at all', () async {
      replies['status'] = {'environment': 'production', 'kid': 7};

      expect(await const VoipChannel().status(), isNull);
    });

    test(
      'passes a rotation, an acknowledgement and the session through',
      () async {
        replies['rotateKey'] = {'kid': 9, 'key': 'bmV3'};

        final rotated = await const VoipChannel().rotateKey();
        await const VoipChannel().ackKey(9);
        await const VoipChannel().setSession(signedIn: false);

        expect(rotated, (kid: 9, key: 'bmV3'));
        expect(calls.map((c) => [c.method, c.arguments]), [
          ['rotateKey', null],
          [
            'ackKey',
            {'kid': 9},
          ],
          [
            'setSession',
            {'signedIn': false},
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

      expect(await const VoipChannel().takeEvents(), [
        VoipEvent.token,
        VoipEvent.keyMismatch,
        VoipEvent.invalidated,
      ]);
    });

    test('exports the test values only from a development build', () async {
      replies['devExport'] = {
        'token': 'abcd',
        'kid': 3,
        'key': 'a2V5',
        'environment': 'development',
      };

      expect(await const VoipChannel().devExport(), (
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

      expect(await const VoipChannel().devExport(), isNull);
    });

    test('a refusal from native code reads as nothing', () async {
      replies['status'] = PlatformException(code: 'keychain');

      expect(await const VoipChannel().status(), isNull);
    });

    test('with the flag off nothing reaches native code', () async {
      ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: false);

      expect(await const VoipChannel().status(), isNull);
      expect(await const VoipChannel().takeEvents(), isEmpty);
      await const VoipChannel().setSession(signedIn: true);
      expect(calls, isEmpty);
    });

    test('on Android nothing reaches native code', () async {
      ambientCapabilities = androidCapabilities;

      expect(await const VoipChannel().devExport(), isNull);
      expect(calls, isEmpty);
    });
  });

  test('without the plugin every call is a quiet no-op', () async {
    expect(await const VoipChannel().status(), isNull);
    expect(await const VoipChannel().takeEvents(), isEmpty);
    expect(await const LaunchChannel().takeWakeReason(), isNull);
  });

  group('the launch channel', () {
    setUp(() => answer(launchChannel));

    test('reports why the app was woken, once', () async {
      replies['takeWakeReason'] = 'ring';

      expect(await const LaunchChannel().takeWakeReason(), WakeReason.ring);
    });

    test('an unknown reason is no reason', () async {
      replies['takeWakeReason'] = 'party';

      expect(await const LaunchChannel().takeWakeReason(), isNull);
    });
  });
}
