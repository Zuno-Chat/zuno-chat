import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/matrix/sync_coordinator.dart';
import 'package:zuno/core/matrix/sync_request_canceller.dart';
import 'package:zuno/core/matrix/undecryptable_event.dart';
import 'package:zuno/core/matrix/zuno_client.dart';

import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

class _BrokenSessionStore extends FakeDatabaseApi {
  bool cleared = false;

  @override
  Future<Map<String, dynamic>?> getClient(String name) async => {
    'client_id': 1,
    'homeserver_url': 'https://example.org',
    'token': 'token',
    'user_id': '@me:example.org',
    'device_id': 'DEVICE',
    'device_name': 'Phone',
  };

  @override
  Future<void> storeClient({
    required String homeserverUrl,
    required String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    required String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  }) async => throw StateError('disk I/O error');

  @override
  Future<void> clear() async => cleared = true;
}

class _SlowLoadingStore extends FakeDatabaseApi {
  final rooms = Completer<List<Room>>();

  @override
  Future<Map<String, dynamic>?> getClient(String name) async => {
    'client_id': 1,
    'homeserver_url': 'https://example.org',
    'token': 'token',
    'user_id': '@me:example.org',
    'device_id': 'DEVICE',
    'device_name': 'Phone',
  };

  @override
  Future<void> storeClient({
    required String homeserverUrl,
    required String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    required String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  }) async {}

  @override
  Future<Map<String, DeviceKeysList>> getUserDeviceKeys(Client client) async =>
      {};

  @override
  Future<List<Room>> getRoomList(Client client) => rooms.future;

  @override
  Future<Map<String, BasicEvent>> getAccountData() async => {};
}

ZunoClient _slowLoadingClient(_SlowLoadingStore store) => ZunoClient(
  'Zuno',
  database: store,
  appClient: false,
  httpClient: FakeHttpClient((_) => Completer<http.Response>().future),
);

class _ClearCountingStore extends FakeDatabaseApi {
  int clears = 0;
  int deletes = 0;

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> delete() async => deletes++;
}

class _ExpiringClient extends ZunoClient {
  _ExpiringClient({required super.database, required super.appClient})
    : super(
        'Zuno',
        onSoftLogout: (_) async => throw MatrixException.fromJson({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'refresh token already used',
        }),
      );

  @override
  DateTime? get accessTokenExpiresAt => clock.now();
}

final _failedWithDiskError = isA<Exception>().having(
  (e) => '$e',
  'cause',
  contains('disk I/O error'),
);

class _PushFetchDatabase extends StoredEventsFakeDatabaseApi {
  @override
  Future<Room?> getSingleRoom(
    Client client,
    String roomId, {
    bool loadImportantStates = true,
  }) async => null;
}

class _PushFetchClient extends ZunoClient with TestDecryption {
  _PushFetchClient()
    : super(
        'test',
        database: _PushFetchDatabase(),
        httpClient: FakeHttpClient((_) async => http.Response('{}', 404)),
      );

  @override
  final FakeRoomDecryption decryption = FakeRoomDecryption();

  @override
  String? get prevBatch => 's1';

  @override
  bool isLogged() => true;

  final syncs = <Duration?>[];
  MatrixEvent? onServer;

  @override
  Future<void> oneShotSync({Duration? timeout}) async => syncs.add(timeout);

  @override
  Future<MatrixEvent> getOneRoomEvent(String roomId, String eventId) async =>
      onServer!;
}

class _SyncingDatabase extends FakeDatabaseApi with SendCapableDatabase {
  @override
  Future<void> forgetRoom(String roomId) async {}

  @override
  Future<void> deleteTimelineForRoom(String roomId) async {}

  @override
  Future<void> storeSyncFilterId(String syncFilterId) async {}

  @override
  Future<void> storePrevBatch(String? prevBatch) async {}

  @override
  Future<void> deleteOldFiles(int savedAt) async {}
}

ZunoClient _syncClient(FakeHttpHandler serve) {
  final client = ZunoClient(
    'Zuno',
    database: _SyncingDatabase(),
    httpClient: FakeHttpClient(
      (request) async => request.url.path.endsWith('/filter')
          ? http.Response(jsonEncode({'filter_id': 'f1'}), 200)
          : serve(request),
    ),
  )..setUserId('@me:example.org');
  client
    ..homeserver = Uri.parse('https://example.org')
    ..bearerToken = 'token'
    ..backgroundSync = false
    ..syncErrorTimeoutSec = 0
    ..importantStateEvents.add('m.call.member');
  return client;
}

Map<String, Object?> _callMember(String eventId, {required int memberships}) =>
    {
      'type': 'm.call.member',
      'state_key': '@bob:example.org',
      'sender': '@bob:example.org',
      'event_id': eventId,
      'origin_server_ts': 1,
      'content': {
        'memberships': [
          for (var i = 0; i < memberships; i++) {'call_id': 'c1'},
        ],
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _BrokenSessionStore store;
  late ZunoClient client;

  setUp(() {
    store = _BrokenSessionStore();
    client = ZunoClient('Zuno', database: store);
  });

  test('a stored session that fails to restore is kept for the next try, '
      'not wiped', () async {
    await expectLater(client.restoreSession(), throwsA(_failedWithDiskError));

    expect(store.cleared, isFalse);
  });

  test('a sign-in that fails while it is being set up still clears what it '
      'half made', () async {
    await expectLater(
      client.init(
        newToken: 'new-token',
        newHomeserver: Uri.parse('https://example.org'),
        newUserID: '@me:example.org',
        newDeviceID: 'NEW',
        newDeviceName: 'Phone',
        waitForFirstSync: false,
      ),
      throwsA(_failedWithDiskError),
    );

    expect(store.cleared, isTrue);
  });

  test(
    'a failed restore does not stop a later sign-out from clearing',
    () async {
      await expectLater(client.restoreSession(), throwsA(_failedWithDiskError));

      await client.clear(reason: SessionClearReason.logout);

      expect(store.cleared, isTrue);
    },
  );

  group('restoring a session', () {
    test('a client that need not wait goes on before its chats are loaded '
        'from the store', () async {
      final slow = _SlowLoadingStore();
      final background = _slowLoadingClient(slow);

      await background
          .restoreSession(waitForStoreLoad: false)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('the store load held up the restore'),
          );

      expect(background.isLogged(), isTrue);
      slow.rooms.complete([]);
      await background.roomsLoading;
    });

    test('any other client waits for its chats, so it can act on a chat '
        'at once', () async {
      final slow = _SlowLoadingStore();
      final client = _slowLoadingClient(slow);
      var restored = false;

      final restoring = client.restoreSession().then((_) => restored = true);
      await pumpEventQueue();
      expect(restored, isFalse);

      slow.rooms.complete([]);
      await restoring;
      expect(restored, isTrue);
    });
  });

  group('a client that is not the app\'s', () {
    test('never clears the shared store, whatever the reason', () async {
      final shared = _ClearCountingStore();
      final background = ZunoClient('Zuno', database: shared, appClient: false);

      for (final reason in SessionClearReason.values) {
        await background.clear(reason: reason);
      }

      expect(shared.clears, 0);
      expect(shared.deletes, 0);
    });

    test('keeps the store when its token refresh is refused', () async {
      final shared = _ClearCountingStore();
      final background = _ExpiringClient(database: shared, appClient: false);

      await expectLater(
        background.ensureNotSoftLoggedOut(),
        throwsA(isA<MatrixException>()),
      );

      expect(shared.clears, 0);
    });
  });

  test('the app\'s client still clears its session when the refresh is '
      'refused', () async {
    final shared = _ClearCountingStore();
    final app = _ExpiringClient(database: shared, appClient: true);

    await expectLater(
      app.ensureNotSoftLoggedOut(),
      throwsA(isA<MatrixException>()),
    );

    expect(shared.clears, 1);
  });

  group('fetching the event a push names', () {
    late _PushFetchClient client;
    late Room room;
    final push = PushNotification(
      devices: const [],
      eventId: r'$event',
      roomId: '!room:example.org',
    );

    setUp(() {
      client = _PushFetchClient()..setUserId('@me:example.org');
      room = buildTestRoom(client, id: '!room:example.org');
      client.onServer = MatrixEvent(
        type: EventTypes.Encrypted,
        content: {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'session_id': 'session',
          'ciphertext': 'sealed',
        },
        senderId: '@bob:example.org',
        eventId: r'$event',
        roomId: room.id,
        originServerTs: DateTime(2026, 10, 28),
      );
    });

    test('hands back an event its key cannot open yet at once, with no sync '
        'to wait for the key', () async {
      client.rooms.add(room);
      client.decryption.decrypted.add(
        lockedTestEvent(room, eventId: r'$event', senderId: '@bob:example.org'),
      );

      final event = await client.getEventByPushNotification(
        push,
        storeInDatabase: false,
      );

      expect(isUndecryptableEvent(event!), isTrue);
      expect(client.decryption.attempts, 1);
      expect(client.syncs, isEmpty);
    });

    test('opens an event whose key is here', () async {
      client.rooms.add(room);
      client.decryption.decrypted.add(
        buildTestEvent(
          room,
          eventId: r'$event',
          senderId: '@bob:example.org',
          content: {'msgtype': MessageTypes.Text, 'body': 'hello'},
        ),
      );

      final event = await client.getEventByPushNotification(
        push,
        storeInDatabase: false,
      );

      expect(event!.body, 'hello');
    });

    test('as the app\'s client, learns a room it does not know only from a '
        'sync already running', () async {
      client.syncCoordinator = SyncCoordinator(
        client,
        SyncRequestCanceller(http.Client()),
      );
      addTearDown(() {
        client.syncCoordinator?.dispose();
        client.syncCoordinator = null;
      });

      final event = await client.getEventByPushNotification(
        push,
        storeInDatabase: false,
      );

      expect(event!.room.id, '!room:example.org');
      expect(client.syncs, isEmpty);
    });

    test('syncs once to learn a room it does not know yet', () async {
      final event = await client.getEventByPushNotification(
        push,
        storeInDatabase: false,
      );

      expect(event!.room.id, '!room:example.org');
      expect(client.syncs, hasLength(1));
    });
  });

  group('the lease', () {
    const channel = MethodChannel('zuno/zuno_client_lease_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'acquire' ? 'lease-7' : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<ClientLease> backgroundLease() => ClientLeases(
      capabilities: androidCapabilities,
      channel: channel,
    ).acquire(ClientLeaseKind.background);

    test('is given back once the client is disposed', () async {
      final background = ZunoClient(
        'Zuno',
        database: FakeDatabaseApi(),
        appClient: false,
        lease: await backgroundLease(),
      );
      expect(calls.map((c) => c.method), ['acquire']);

      await background.dispose(closeDatabase: false);

      expect(calls.map((c) => c.method), ['acquire', 'release']);
      expect(calls.last.arguments, {'token': 'lease-7'});
    });
  });

  group('room state at the end of each sync', () {
    const roomId = '!room:example.org';

    Future<ZunoClient> synced(Map<String, Object?> rooms) async {
      final client = _syncClient(
        (_) async => http.Response(
          jsonEncode({'next_batch': 's2', 'rooms': rooms}),
          200,
        ),
      );
      await client.oneShotSync(timeout: Duration.zero);
      return client;
    }

    List<Object?>? memberships(ZunoClient client) =>
        client
                .getRoomById(roomId)
                ?.getState('m.call.member', '@bob:example.org')
                ?.content['memberships']
            as List<Object?>?;

    test('is asked for on every sync', () async {
      Uri? asked;
      final client = _syncClient((request) async {
        if (request.url.path.endsWith('/sync')) asked = request.url;
        return http.Response(jsonEncode({'next_batch': 's2'}), 200);
      });

      await client.oneShotSync(timeout: Duration.zero);

      expect(asked!.queryParameters['use_state_after'], 'true');
    });

    test('reaches a joined room through the sync loop', () async {
      final client = await synced({
        'join': {
          roomId: {
            'state_after': {
              'events': [_callMember(r'$left', memberships: 0)],
            },
          },
        },
      });

      expect(memberships(client), isEmpty);
    });

    test('keeps a newly joined room encrypted, so nothing goes out in the '
        'clear', () async {
      final client = await synced({
        'join': {
          roomId: {
            'state_after': {
              'events': [
                {
                  'type': EventTypes.Encryption,
                  'state_key': '',
                  'sender': '@bob:example.org',
                  'event_id': r'$encryption',
                  'origin_server_ts': 1,
                  'content': {'algorithm': AlgorithmTypes.megolmV1AesSha2},
                },
              ],
            },
          },
        },
      });

      expect(client.getRoomById(roomId)!.encrypted, isTrue);
    });

    test(
      'a server that still sends the state at the start keeps working',
      () async {
        final client = await synced({
          'join': {
            roomId: {
              'state': {
                'events': [_callMember(r'$joined', memberships: 1)],
              },
            },
          },
        });

        expect(memberships(client), hasLength(1));
      },
    );

    test('a room left during the sync still gets its final state', () async {
      final client = _syncClient(
        (_) async => http.Response(
          jsonEncode({
            'next_batch': 's2',
            'rooms': {
              'leave': {
                roomId: {
                  'state_after': {
                    'events': [_callMember(r'$left', memberships: 0)],
                  },
                },
              },
            },
          }),
          200,
        ),
      );
      final applied = <String?>[];
      client.onRoomState.stream.listen((u) => applied.add(u.state.stateKey));

      await client.oneShotSync(timeout: Duration.zero);
      await pumpEventQueue();

      expect(applied, ['@bob:example.org']);
    });
  });
}
