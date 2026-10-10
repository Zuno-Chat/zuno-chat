import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm_bridge.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/fcm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];
  Object? answer;

  setUp(() {
    calls.clear();
    answer = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final reply = answer;
      if (reply is Exception) throw reply;
      return reply;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  Future<Object?> fromNative(String method, Object? arguments) =>
      callFromNative(channel, method, arguments);

  group('availability', () {
    test('parses each answer the native side gives', () async {
      for (final entry in {
        'available': FcmAvailability.available,
        'updateRequired': FcmAvailability.updateRequired,
        'disabled': FcmAvailability.disabled,
        'unavailable': FcmAvailability.unavailable,
        'notConfigured': FcmAvailability.notConfigured,
        'unknown': FcmAvailability.unknown,
      }.entries) {
        answer = entry.key;
        expect(await FcmBridge().availability(), entry.value);
      }
      expect(calls, everyElement('availability'));
    });

    test('an answer it does not know is unknown, never available or '
        'unavailable', () async {
      for (final unclear in ['somethingElse', null]) {
        answer = unclear;
        expect(await FcmBridge().availability(), FcmAvailability.unknown);
      }
    });

    test('a failing channel is unknown, not unavailable and not a '
        'crash', () async {
      for (final failure in [
        PlatformException(code: 'error'),
        MissingPluginException('no handler'),
      ]) {
        answer = failure;
        expect(await FcmBridge().availability(), FcmAvailability.unknown);
      }
    });

    test('a fix reports the availability once Google is done', () async {
      answer = 'available';
      expect(await FcmBridge().fixPlayServices(), FcmAvailability.available);
      expect(calls, ['fixPlayServices']);
    });

    test('a refused fix asks again instead of guessing', () async {
      var asked = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'fixPlayServices') {
          throw PlatformException(code: 'error');
        }
        asked++;
        return 'updateRequired';
      });
      expect(
        await FcmBridge().fixPlayServices(),
        FcmAvailability.updateRequired,
      );
      expect(asked, 1);
    });
  });

  group('getToken', () {
    test('returns the token', () async {
      answer = 'token-abc';
      expect(await FcmBridge().getToken(), 'token-abc');
      expect(calls, ['getToken']);
    });

    test('an empty token is no token', () async {
      answer = '';
      expect(await FcmBridge().getToken(), isNull);
    });

    for (final entry in {
      'noPlayServices': FcmTokenFailure.noPlayServices,
      'notConfigured': FcmTokenFailure.notConfigured,
      'unavailable': FcmTokenFailure.unavailable,
      'failed': FcmTokenFailure.failed,
      'somethingElse': FcmTokenFailure.failed,
    }.entries) {
      test('maps the ${entry.key} failure', () async {
        answer = PlatformException(code: entry.key, message: 'why');
        await expectLater(
          FcmBridge().getToken(),
          throwsA(
            isA<FcmTokenException>()
                .having((e) => e.failure, 'failure', entry.value)
                .having((e) => e.message, 'message', 'why'),
          ),
        );
      });
    }

    test('a missing native side is a plain failure', () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        FcmBridge().getToken(),
        throwsA(
          isA<FcmTokenException>().having(
            (e) => e.failure,
            'failure',
            FcmTokenFailure.failed,
          ),
        ),
      );
    });
  });

  test('deleteToken asks the native side', () async {
    await FcmBridge().deleteToken();
    expect(calls, ['deleteToken']);
  });

  group('ready', () {
    test('reports that the native side took this engine', () async {
      answer = true;
      expect(await FcmBridge().ready(), isTrue);
      expect(calls, ['ready']);
    });

    test(
      'counts a no, or an answer that is not a yes, as passed over',
      () async {
        for (final reply in [false, null]) {
          answer = reply;
          expect(await FcmBridge().ready(), isFalse, reason: '$reply');
        }
      },
    );

    test('survives a failure, which counts as passed over', () async {
      answer = PlatformException(code: 'error');
      expect(await FcmBridge().ready(), isFalse);
      expect(calls, ['ready']);
    });
  });

  group('serve', () {
    test(
      'hands a push to the handler and replies once it is handled',
      () async {
        final handled = Completer<void>();
        final pushes = <FcmPush>[];
        FcmBridge().serve(
          onPush: (push) async {
            pushes.add(push);
            await handled.future;
          },
        );

        var replied = false;
        final reply = fromNative('push', {
          'id': 'm1',
          'data': {'event_id': r'$e', 'room_id': '!r:x', 'unread': '2'},
          'appInFront': true,
        }).then((_) => replied = true);
        await pumpEventQueue();

        expect(pushes.single.id, 'm1');
        expect(pushes.single.appInFront, isTrue);
        expect(pushes.single.data, {
          'event_id': r'$e',
          'room_id': '!r:x',
          'unread': '2',
        });
        expect(replied, isFalse);

        handled.complete();
        await reply;
        expect(replied, isTrue);
      },
    );

    test(
      'a throwing handler still replies, so the native side moves on',
      () async {
        FcmBridge().serve(onPush: (_) async => throw StateError('boom'));

        await expectLater(
          fromNative('push', {'id': 'm1', 'data': <String, String>{}}),
          throwsA(isA<PlatformException>()),
        );
      },
    );

    test('a push without an id or data is answered and ignored', () async {
      final pushes = <FcmPush>[];
      FcmBridge().serve(onPush: (push) async => pushes.add(push));

      await fromNative('push', {'data': <String, String>{}});
      await fromNative('push', 'garbage');

      expect(pushes, isEmpty);
    });

    test('a push that does not say where the app is counts as not in '
        'front', () async {
      final pushes = <FcmPush>[];
      FcmBridge().serve(onPush: (push) async => pushes.add(push));

      await fromNative('push', {'id': 'm1', 'data': <String, String>{}});

      expect(pushes.single.appInFront, isFalse);
    });

    test('says whether its engine is quiet enough to stop', () async {
      var quiet = false;
      FcmBridge().serve(onPush: (_) async {}, isQuiescent: () async => quiet);

      expect(await fromNative('quiescent', null), isFalse);
      quiet = true;
      expect(await fromNative('quiescent', null), isTrue);
    });

    test(
      'answers whether it is quiet only once the engine has settled',
      () async {
        final settled = Completer<bool>();
        FcmBridge().serve(
          onPush: (_) async {},
          isQuiescent: () => settled.future,
        );

        Object? answer = 'no answer yet';
        final reply = fromNative('quiescent', null).then((a) => answer = a);
        await pumpEventQueue();
        expect(answer, 'no answer yet');

        settled.complete(true);
        await reply;
        expect(answer, isTrue);
      },
    );

    test('an engine that fails to settle is not quiet', () async {
      FcmBridge().serve(
        onPush: (_) async {},
        isQuiescent: () async => throw StateError('dispose failed'),
      );

      expect(await fromNative('quiescent', null), isFalse);
    });

    test('an engine that cannot tell is never quiet', () async {
      FcmBridge().serve(onPush: (_) async {});

      expect(await fromNative('quiescent', null), isFalse);
    });

    test('hands a new token to its handler', () async {
      final tokens = <String>[];
      FcmBridge().serve(
        onPush: (_) async {},
        onToken: (token) async => tokens.add(token),
      );

      await fromNative('token', {'token': 'fresh'});

      expect(tokens, ['fresh']);
    });

    test(
      'without a token handler a new token goes to tokenRefreshes',
      () async {
        final bridge = FcmBridge()..serve(onPush: (_) async {});
        final tokens = <String>[];
        final sub = bridge.tokenRefreshes.listen(tokens.add);

        await fromNative('token', {'token': 'fresh'});
        await pumpEventQueue();

        expect(tokens, ['fresh']);
        await sub.cancel();
      },
    );
  });

  group('on a platform without FCM', () {
    final bridge = FcmBridge(capabilities: iosCapabilities);

    test('nothing reaches the native side', () async {
      expect(await bridge.availability(), FcmAvailability.unavailable);
      expect(await bridge.fixPlayServices(), FcmAvailability.unavailable);
      expect(await bridge.getToken(), isNull);
      await bridge.deleteToken();
      expect(await bridge.ready(), isFalse);
      expect(calls, isEmpty);
    });

    test('serve registers no handler', () async {
      final pushes = <FcmPush>[];
      bridge.serve(onPush: (push) async => pushes.add(push));

      final reply = await fromNative('push', {
        'id': 'm1',
        'data': <String, String>{},
      });

      expect(reply, isNull);
      expect(pushes, isEmpty);
    });
  });
}
