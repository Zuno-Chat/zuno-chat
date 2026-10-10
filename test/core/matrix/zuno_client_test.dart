import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/matrix/zuno_client.dart';

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
  Future<void> updateClient(
    String homeserverUrl,
    String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  ) async => throw StateError('disk I/O error');

  @override
  Future<void> clear() async => cleared = true;
}

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
  DateTime? get accessTokenExpiresAt => DateTime.now();
}

final _failedWithDiskError = isA<Exception>().having(
  (e) => '$e',
  'cause',
  contains('disk I/O error'),
);

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
}
