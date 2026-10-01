import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/headless_push_runner.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';
import 'package:zuno/core/push/unified_push_headless_entry.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi());

  int disposeCalls = 0;

  @override
  Future<void> dispose({bool closeDatabase = true}) async => disposeCalls++;
}

class _RingingClient extends Client {
  _RingingClient({this.rings = true})
    : super('test', database: FakeDatabaseApi()) {
    setUserId('@me:example.org');
  }

  final bool rings;

  @override
  bool isLogged() => true;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    if (!rings) return null;
    final room = buildTestRoom(this);
    return buildTestEvent(
      room,
      eventId: r'$invite',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now(),
      content: const {
        'msgtype': 'im.zuno.call_invite',
        'call_id': 'call1',
        'kind': 'voice',
        'body': 'Incoming call',
      },
    );
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {}
}

PushMessage _push(String eventId) => PushMessage(
  utf8.encode(
    jsonEncode({
      'notification': {'event_id': eventId, 'room_id': '!room:example.org'},
    }),
  ),
  true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
        return _RecordingClient();
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
        return _RecordingClient();
      },
      initializeNotifications: () async {},
      releaseWakeLock: ({key}) async {},
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    await provider.deliverPushForTest(
      PushMessage(
        utf8.encode(
          jsonEncode({
            'notification': {
              'counts': {'unread': 0},
            },
          }),
        ),
        true,
      ),
    );

    expect(builds, 0);
    expect(provider.lastPushOutcome, IncomingPushOutcome.badge);
  });

  test('gives its idle client up when the app asks for it, and lets it go '
      'by itself after ten idle minutes', () async {
    final requests = StreamController<void>.broadcast();
    addTearDown(requests.close);
    final built = <_RecordingClient>[];
    final provider = UnifiedPushDeliveryProvider();
    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async {
        final client = _RecordingClient();
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
    final provider = UnifiedPushDeliveryProvider();

    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async => _RecordingClient(),
      initializeNotifications: () async => throw StateError('no channel'),
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    expect(provider.runner.clientBuilder, isNotNull);
  });

  group('the push wake lock', () {
    late UnifiedPushDeliveryProvider provider;
    late int releases;
    late int holds;
    late Completer<void> ringOver;

    setUp(() {
      ringRateLimiter.clear();
      installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      installFakeCallStyleChannel();
      for (final name in ['zuno/calls', 'zuno/vibration']) {
        final side = MethodChannel(name);
        messenger.setMockMethodCallHandler(side, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(side, null));
      }
      const lock = MethodChannel('zuno/push_wakelock');
      messenger.setMockMethodCallHandler(lock, (call) async {
        if (call.method == 'release') releases++;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(lock, null));
      provider = UnifiedPushDeliveryProvider();
      releases = 0;
      holds = 0;
      ringOver = Completer<void>();
    });

    Future<void> start({required bool rings}) => runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async => _RingingClient(rings: rings),
      initializeNotifications: () async {},
      hold: (_) {
        holds++;
        return ringOver.future;
      },
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    test('is let go once for a ringing push, after the ring hold', () async {
      await start(rings: true);

      final delivery = provider.deliverPushForTest(_push(r'$invite'));
      await pumpEventQueue();
      expect(provider.lastPushOutcome, IncomingPushOutcome.callRinging);
      expect(holds, 1);
      expect(releases, 0);

      ringOver.complete();
      await delivery;
      expect(releases, 1);
    });

    test('is let go once for any other push, with no hold', () async {
      await start(rings: false);

      await provider.deliverPushForTest(_push(r'$text'));

      expect(holds, 0);
      expect(releases, 1);
    });
  });

  group('answerQuiescence', () {
    const channel = MethodChannel('zuno/push_wakelock');

    tearDown(() => channel.setMethodCallHandler(null));

    Future<Object?> ask(String method) {
      final replied = Completer<Object?>();
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method)),
        (data) {
          try {
            replied.complete(
              data == null ? null : channel.codec.decodeEnvelope(data),
            );
          } catch (error) {
            replied.completeError(error);
          }
        },
      );
      return replied.future;
    }

    test('is quiet for an engine that has done nothing', () async {
      answerQuiescence(HeadlessPushRunner());

      expect(await ask('quiescent'), isTrue);
    });

    test('lets go of a client nobody used, then answers quiet', () async {
      final client = _RecordingClient();
      final runner = HeadlessPushRunner()..clientBuilder = () async => client;
      answerQuiescence(runner);

      runner.prepareClient();

      expect(await ask('quiescent'), isTrue);
      expect(client.disposeCalls, 1);
    });

    test('is not quiet while a push is being handled', () async {
      final handling = Completer<void>();
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => _RecordingClient();
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
