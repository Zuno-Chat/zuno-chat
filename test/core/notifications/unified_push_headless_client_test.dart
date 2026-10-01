import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient({this.signedIn = true})
    : super('test', database: FakeDatabaseApi());

  final bool signedIn;
  int disposeCalls = 0;
  bool? closedDatabase;
  int resolveCalls = 0;

  @override
  bool isLogged() => signedIn;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    resolveCalls++;
    return null;
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposeCalls++;
    closedDatabase = closeDatabase;
  }
}

class _BrokenClient extends Client {
  _BrokenClient() : super('test', database: FakeDatabaseApi());

  @override
  bool isLogged() => throw StateError('database closed');
}

Uint8List _pushBytes({String eventId = '\$abc'}) => utf8.encode(
  jsonEncode({
    'notification': {'event_id': eventId, 'room_id': '!room:example.org'},
  }),
);

Uint8List _badgeBytes() => utf8.encode(
  jsonEncode({
    'notification': {
      'counts': {'unread': 2},
    },
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UnifiedPushDeliveryProvider provider;
  late List<_RecordingClient> built;
  late List<IncomingPushOutcome> handled;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = UnifiedPushDeliveryProvider();
    built = [];
    handled = [];
  });

  Future<Client> buildClient() async {
    final client = _RecordingClient();
    built.add(client);
    return client;
  }

  Future<void> registerHeadless() => provider.ensureHeadlessCallbacksRegistered(
    clientBuilder: buildClient,
    onPushHandled: (outcome) async => handled.add(outcome),
  );

  Future<void> deliver({String eventId = '\$abc'}) => provider
      .deliverPushForTest(PushMessage(_pushBytes(eventId: eventId), true));

  test('back-to-back pushes share one client, let go without closing the '
      'database', () async {
    await registerHeadless();

    await deliver(eventId: '\$one');
    await deliver(eventId: '\$two');

    expect(built, hasLength(1));
    expect(built.single.resolveCalls, 2);
    expect(built.single.disposeCalls, 0);

    expect(await provider.runner.settle(), isTrue);
    expect(built.single.disposeCalls, 1);
    expect(built.single.closedDatabase, isFalse);
  });

  test('onPushHandled runs once the push is done with its client, so a '
      'decline from it reuses that client', () async {
    Client? declinedWith;
    await provider.ensureHeadlessCallbacksRegistered(
      clientBuilder: buildClient,
      onPushHandled: (outcome) async {
        handled.add(outcome);
        declinedWith = await provider.withClient((client) async => client);
      },
    );

    await deliver();

    expect(handled, [IncomingPushOutcome.ignored]);
    expect(built, hasLength(1));
    expect(declinedWith, same(built.single));
  });

  test(
    'a push held open by a ringing call still lets the next one through',
    () async {
      final ringing = Completer<void>();
      await provider.ensureHeadlessCallbacksRegistered(
        clientBuilder: buildClient,
        onPushHandled: (outcome) async {
          handled.add(outcome);
          if (handled.length == 1) await ringing.future;
        },
      );

      final first = deliver(eventId: '\$ring');
      await pumpEventQueue();
      final second = deliver(eventId: '\$hangup');
      await pumpEventQueue();

      expect(
        built.single.resolveCalls,
        2,
        reason: 'the hang-up must be handled while the ring is still held',
      );

      ringing.complete();
      await Future.wait([first, second]);
    },
  );

  test('a push that cannot be decoded never opens a client', () async {
    await registerHeadless();

    await provider.deliverPushForTest(
      PushMessage(utf8.encode('not json'), true),
    );

    expect(built, isEmpty);
    expect(handled, isEmpty);
  });

  test('a client that fails to open is swallowed, not thrown', () async {
    await provider.ensureHeadlessCallbacksRegistered(
      clientBuilder: () async => throw StateError('database unavailable'),
      onPushHandled: (outcome) async => handled.add(outcome),
    );

    await expectLater(
      provider.deliverPushForTest(PushMessage(_pushBytes(), true)),
      completes,
    );
    expect(handled, isEmpty);
  });

  group('the push wake lock', () {
    const channel = MethodChannel('zuno/push_wakelock');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> calls;
    late List<Object?> releasedFor;

    int releases() => calls.where((c) => c == 'release').length;

    setUp(() {
      calls = [];
      releasedFor = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'release') releasedFor.add(call.arguments);
        return call.method == 'appInFront' ? true : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    group('in the app', () {
      test('is let go once its push is handled', () async {
        await provider.ensureCallbacksRegistered(_RecordingClient());

        await deliver();

        expect(calls, ['release']);
      });

      test('names the push it was held for when letting go', () async {
        await provider.ensureCallbacksRegistered(_RecordingClient());

        await deliver(eventId: r'$held');

        expect(releasedFor, [
          {'key': r'$held'},
        ]);
      });

      test('is let go for a push it cannot read', () async {
        await provider.ensureCallbacksRegistered(_RecordingClient());

        await provider.deliverPushForTest(
          PushMessage(utf8.encode('not json'), true),
        );

        expect(calls, ['release']);
      });

      test('is let go once for a push left to the app\'s own sync', () async {
        await provider.ensureCallbacksRegistered(_RecordingClient());
        provider.runner.isAppSyncing = () => true;

        await deliver();

        expect(releases(), 1);
      });

      test('is let go once for a push whose handling fails', () async {
        await provider.ensureCallbacksRegistered(_BrokenClient());

        await deliver();

        expect(releases(), 1);
      });
    });

    group('in a headless engine', () {
      test('is let go once its push is handled', () async {
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: buildClient,
          onPushHandled: (outcome) async {
            handled.add(outcome);
            expect(calls, isEmpty, reason: 'released before the push ended');
          },
        );

        await deliver();

        expect(handled, [IncomingPushOutcome.ignored]);
        expect(calls, ['release']);
      });

      test('is let go only after a ring hold ends', () async {
        final holdOver = Completer<void>();
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: buildClient,
          onPushHandled: (_) => holdOver.future,
        );

        final delivery = deliver();
        await pumpEventQueue();
        expect(calls, isEmpty);

        holdOver.complete();
        await delivery;
        expect(calls, ['release']);
      });

      test('is let go for a push it cannot read', () async {
        await registerHeadless();

        await provider.deliverPushForTest(
          PushMessage(utf8.encode('not json'), true),
        );

        expect(calls, ['release']);
      });

      test('is let go when no client can be opened', () async {
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: () async => throw StateError('database unavailable'),
          onPushHandled: (outcome) async => handled.add(outcome),
        );

        await deliver();

        expect(calls, ['release']);
      });

      test('is let go once for a badge-only push', () async {
        await registerHeadless();

        await provider.deliverPushForTest(PushMessage(_badgeBytes(), true));

        expect(handled, [IncomingPushOutcome.badge]);
        expect(calls, ['release']);
      });

      test('is let go once for a signed-out push', () async {
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: () async => _RecordingClient(signedIn: false),
          onPushHandled: (outcome) async => handled.add(outcome),
        );

        await deliver();

        expect(calls, ['release']);
      });
    });
  });

  test('the main isolate keeps its long-lived client', () async {
    final client = _RecordingClient();
    await provider.ensureCallbacksRegistered(client);

    await provider.deliverPushForTest(PushMessage(_pushBytes(), true));

    expect(client.resolveCalls, 1);
    expect(client.disposeCalls, 0);
    expect(built, isEmpty);
  });
}
