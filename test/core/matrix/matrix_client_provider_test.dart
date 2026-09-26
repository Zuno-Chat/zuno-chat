import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/matrix/database_key.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/vodozemac_init.dart';

import '../../helpers/fake_matrix.dart';

class _FakeVerification extends Fake implements KeyVerification {}

void main() {
  Future<List<bool>> loginStatesAfter(List<LoginState> emitted) async {
    final client = buildTestClient()..accessToken = 'a0';
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final seen = <bool>[];
    container.listen(isLoggedInProvider, (_, next) {
      final loggedIn = next.value;
      if (loggedIn != null) seen.add(loggedIn);
    }, fireImmediately: true);
    await container.read(isLoggedInProvider.future);
    await pumpEventQueue();

    for (final state in emitted) {
      client.onLoginStateChanged.add(state);
      await pumpEventQueue();
    }
    return seen;
  }

  test('a token refresh never reads as signed out', () async {
    final seen = await loginStatesAfter([
      LoginState.softLoggedOut,
      LoginState.loggedIn,
    ]);

    expect(seen, isNot(contains(false)));
  });

  test('a refresh that fails without a verdict stays signed in', () async {
    final seen = await loginStatesAfter([LoginState.softLoggedOut]);

    expect(seen.last, isTrue);
  });

  test('a cleared session signs out', () async {
    final seen = await loginStatesAfter([
      LoginState.softLoggedOut,
      LoginState.loggedOut,
    ]);

    expect(seen.last, isFalse);
  });

  for (final (label, provider) in [
    ('the client', matrixClientProvider),
    ('the upload client', uploadProgressHttpClientProvider),
  ]) {
    test('using $label before it is set up fails loudly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(provider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });
  }

  test('hands on each incoming verification request', () async {
    final client = buildTestClient();
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final request = _FakeVerification();

    final seen = <KeyVerification>[];
    container.listen(incomingKeyVerificationProvider, (_, next) {
      if (next.value case final verification?) seen.add(verification);
    });

    client.onKeyVerificationRequest.add(request);
    await pumpEventQueue();

    expect(seen, [same(request)]);
  });

  group('createMatrixClient', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const sqlcipher = MethodChannel('com.davidmartos96.sqflite_sqlcipher');

    late Directory support;
    late Map<String, String> secrets;
    late List<Map<Object?, Object?>> opened;
    late List<List<Object?>> cipherVersionRows;

    setUp(() async {
      support = Directory.systemTemp.createTempSync('zuno_support');
      secrets = {};
      opened = [];
      cipherVersionRows = [
        ['4.6.1 community'],
      ];
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => call.method == 'getApplicationSupportDirectory'
            ? support.path
            : null,
      );
      messenger.setMockMethodCallHandler(secureStorage, (call) async {
        final args = (call.arguments as Map).cast<String, Object?>();
        return switch (call.method) {
          'read' => secrets[args['key']],
          'write' => secrets[args['key'] as String] = args['value'] as String,
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(sqlcipher, (call) async {
        final args = call.arguments is Map ? call.arguments as Map : const {};
        switch (call.method) {
          case 'openDatabase':
            opened.add(args);
            return opened.length;
          case 'query':
            return '${args['sql']}'.contains('cipher_version')
                ? {
                    'columns': ['cipher_version'],
                    'rows': cipherVersionRows,
                  }
                : {'columns': <String>[], 'rows': <List<Object?>>[]};
          case 'batch':
            return [
              for (final _ in args['operations'] as List) {'result': null},
            ];
          case 'insert' || 'update':
            return 1;
          default:
            return null;
        }
      });
      await ensureVodozemacInitialized(init: () async {});
      addTearDown(() {
        resetVodozemacInitForTest();
        for (final channel in [pathProvider, secureStorage, sqlcipher]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        support.deleteSync(recursive: true);
      });
    });

    Future<Client> create({bool backgroundSync = true}) async {
      final created = await createMatrixClient(backgroundSync: backgroundSync);
      addTearDown(created.client.dispose);
      expect(
        (created.client.httpClient as dynamic).inner,
        same(created.uploadProgressHttpClient),
      );
      return created.client;
    }

    test('opens the database encrypted with the stored key', () async {
      await create();

      final open = opened.single;
      expect(open['path'], '${support.path}/zuno.db');
      expect(open['password'], hasLength(databaseCipherLength));
      expect(secrets.values, contains(open['password']));
    });

    test('opens it with the same key on the next start', () async {
      final previousRun = await createMatrixClient();
      await previousRun.client.dispose();

      await create();

      expect(opened, hasLength(2));
      expect(opened.last['password'], opened.first['password']);
    });

    test('starts signed out when nothing is stored', () async {
      final client = await create();

      expect(client.isLogged(), isFalse);
      expect(client.onLoginStateChanged.value, LoginState.loggedOut);
    });

    test('is set up for Zuno', () async {
      final client = await create();

      expect(client.clientName, 'Zuno');
      expect(client.importantStateEvents, contains(callMemberEventType));
      expect(
        client.roomPreviewLastEvents,
        containsAll({
          EventTypes.Message,
          EventTypes.Encrypted,
          EventTypes.Sticker,
        }),
      );
      expect(client.verificationMethods, {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.qrShow,
        KeyVerificationMethod.qrScan,
      });
      expect(client.syncErrorTimeoutSec, 1);
    });

    test('the app client does crypto off the UI thread', () async {
      final client = await create();

      expect(client.nativeImplementations, isA<NativeImplementationsIsolate>());
    });

    test('a headless client does crypto in place', () async {
      final client = await create(backgroundSync: false);

      expect(
        client.nativeImplementations,
        isNot(isA<NativeImplementationsIsolate>()),
      );
    });

    for (final (label, rows) in [
      ('no cipher version', <List<Object?>>[]),
      (
        'an empty cipher version',
        [
          <Object?>[null],
        ],
      ),
    ]) {
      test('refuses a database with $label, never writing plaintext', () async {
        cipherVersionRows = rows;

        await expectLater(
          createMatrixClient(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('SQLCipher is not available'),
            ),
          ),
        );
      });
    }
  });
}
