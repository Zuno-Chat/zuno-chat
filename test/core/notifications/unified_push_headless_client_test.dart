import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi());

  int disposeCalls = 0;
  bool? closedDatabase;
  int resolveCalls = 0;

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

Uint8List _pushBytes({String eventId = '\$abc'}) => utf8.encode(
  jsonEncode({
    'notification': {'event_id': eventId, 'room_id': '!room:example.org'},
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

  Future<void> registerHeadless() => provider.ensureHeadlessCallbacksRegistered(
    clientBuilder: () async {
      final client = _RecordingClient();
      built.add(client);
      return client;
    },
    onPushHandled: (outcome) async => handled.add(outcome),
  );

  Future<void> deliver({String eventId = '\$abc'}) => provider
      .deliverPushForTest(PushMessage(_pushBytes(eventId: eventId), true));

  test('each push gets its own client, disposed when it is done', () async {
    await registerHeadless();

    await deliver(eventId: '\$one');
    await deliver(eventId: '\$two');

    expect(built, hasLength(2));
    expect(built[0].resolveCalls, 1);
    expect(built[1].resolveCalls, 1);
    for (final client in built) {
      expect(client.disposeCalls, 1);
      expect(client.closedDatabase, isFalse);
    }
  });

  test('onPushHandled runs once this push has let go of its client', () async {
    await registerHeadless();

    await deliver();

    expect(handled, hasLength(1));
    expect(handled.single, IncomingPushOutcome.ignored);
    expect(built.single.disposeCalls, 1);
  });

  test('a push held open by a ringing call still lets the next one through', () async {
    final ringing = Completer<void>();
    await provider.ensureHeadlessCallbacksRegistered(
      clientBuilder: () async {
        final client = _RecordingClient();
        built.add(client);
        return client;
      },
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
      built,
      hasLength(2),
      reason: 'the hang-up must be handled while the ring is still held',
    );
    expect(built[1].resolveCalls, 1);

    ringing.complete();
    await Future.wait([first, second]);
  });

  test('a decline during the ring can still get a client', () async {
    await registerHeadless();

    final client = await provider.withClient((client) async => client);

    expect(client, isNotNull);
    expect(built, hasLength(1));
    expect(built.single.disposeCalls, 1);
  });

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

  test('the main isolate keeps its long-lived client', () async {
    final client = _RecordingClient();
    await provider.ensureCallbacksRegistered(client);

    await provider.deliverPushForTest(PushMessage(_pushBytes(), true));

    expect(client.resolveCalls, 1);
    expect(client.disposeCalls, 0);
    expect(built, isEmpty);
  });
}
