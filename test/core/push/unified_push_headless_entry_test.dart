import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/headless_push_runner.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';
import 'package:zuno/core/push/unified_push_headless_entry.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/headless_ring.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/push_test_client.dart';

PushMessage _push(String eventId) => PushMessage(
  utf8.encode(
    jsonEncode({
      'notification': {'event_id': eventId, 'room_id': '!room:example.org'},
    }),
  ),
  true,
);

PushMessage _badgePush() => PushMessage(
  utf8.encode(
    jsonEncode({
      'notification': {
        'counts': {'unread': 0},
      },
    }),
  ),
  true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('registers the callbacks and sets up notifications without opening '
      'a client before a push needs one', () async {
    var builds = 0;
    var setups = 0;
    final provider = UnifiedPushDeliveryProvider();

    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async {
        builds++;
        return PushTestClient();
      },
      initializeNotifications: () async => setups++,
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    expect(builds, 0);
    expect(setups, 1);
    expect(provider.runner.clientBuilder, isNotNull);
    expect(provider.runner.onPushHandled, isNotNull);
  });

  test('a badge-only push opens no client', () async {
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    var builds = 0;
    final provider = UnifiedPushDeliveryProvider();
    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async {
        builds++;
        return PushTestClient();
      },
      initializeNotifications: () async {},
      releaseWakeLock: ({key}) async {},
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    await provider.deliverPushForTest(_badgePush());

    expect(builds, 0);
    expect(provider.lastPushOutcome, IncomingPushOutcome.badge);
  });

  test('gives its idle client up when the app asks for it, and lets it go '
      'by itself after ten idle minutes', () async {
    final requests = StreamController<void>.broadcast();
    addTearDown(requests.close);
    final built = <PushTestClient>[];
    final provider = UnifiedPushDeliveryProvider();
    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async {
        final client = PushTestClient();
        built.add(client);
        return client;
      },
      initializeNotifications: () async {},
      releaseWakeLock: ({key}) async {},
      firstCallbackTimeout: const Duration(milliseconds: 20),
      yieldRequests: requests.stream,
    );
    expect(provider.runner.idleLimit, const Duration(minutes: 10));

    await provider.deliverPushForTest(_push(r'$text'));
    expect(built.single.disposeCalls, 0);

    requests.add(null);
    await pumpEventQueue();

    expect(built.single.disposeCalls, 1);
  });

  test('a failed notification setup still leaves the handler waiting for '
      'the push instead of crashing the engine', () async {
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    final provider = UnifiedPushDeliveryProvider();

    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async => PushTestClient(),
      initializeNotifications: () async => throw StateError('no channel'),
      releaseWakeLock: ({key}) async {},
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );
    await provider.deliverPushForTest(_badgePush());

    expect(provider.lastPushOutcome, IncomingPushOutcome.badge);
  });

  group('the ring hold', () {
    late UnifiedPushDeliveryProvider provider;
    late RecordedMethodCalls lock;
    late int holds;
    late Completer<void> ringOver;

    setUp(() {
      installHeadlessRingChannels();
      lock = recordMethodChannel('zuno/push_wakelock');
      provider = UnifiedPushDeliveryProvider();
      holds = 0;
      ringOver = Completer<void>();
    });

    Future<void> start({required bool rings}) => runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async => ringingPushClient(rings: rings),
      initializeNotifications: () async {},
      hold: (_) {
        holds++;
        return ringOver.future;
      },
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    test(
      'keeps a ringing push, and its wake lock, until the ring ends',
      () async {
        await start(rings: true);

        final delivery = provider.deliverPushForTest(_push(r'$invite'));
        await pumpEventQueue();
        expect(provider.lastPushOutcome, IncomingPushOutcome.callRinging);
        expect(holds, 1);
        expect(lock.count('release'), 0);

        ringOver.complete();
        await delivery;
        expect(lock.count('release'), 1);
      },
    );

    test('is not started for any other push', () async {
      await start(rings: false);

      await provider.deliverPushForTest(_push(r'$text'));

      expect(provider.lastPushOutcome, IncomingPushOutcome.ignored);
      expect(holds, 0);
    });
  });

  group('answerQuiescence', () {
    const channel = MethodChannel('zuno/push_wakelock');

    tearDown(() => channel.setMethodCallHandler(null));

    Future<Object?> ask(String method) => callFromNative(channel, method);

    test('is quiet for an engine that has done nothing', () async {
      answerQuiescence(HeadlessPushRunner());

      expect(await ask('quiescent'), isTrue);
    });

    test('is not quiet while a push is being handled', () async {
      final handling = Completer<void>();
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => PushTestClient();
      answerQuiescence(runner);

      final push = runner.withClient((_) => handling.future);
      await pumpEventQueue();

      expect(await ask('quiescent'), isFalse);
      handling.complete();
      await push;
    });

    test('answers nothing else', () async {
      answerQuiescence(HeadlessPushRunner());

      expect(await ask('somethingElse'), isNull);
    });
  });
}
