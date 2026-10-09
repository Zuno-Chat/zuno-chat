import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import '../calls/matrixrtc/call_member_state.dart' show callMemberEventType;
import '../errors/best_effort.dart';
import '../location/live_location_protocol.dart' show liveLocationStateType;
import '../platform/platform_capabilities.dart';
import '../push/read_model/session_exporter.dart';
import '../push/send_keep_awake.dart';
import 'atomic_batch_database.dart';
import 'client_lease.dart';
import 'client_startup.dart';
import 'database_compaction.dart';
import 'database_key.dart';
import 'database_raw_key.dart';
import 'ephemeral_to_device.dart';
import 'fresh_token_http_client.dart';
import 'sdk_logs.dart';
import 'session_refresh.dart';
import 'upload_progress_http_client.dart';
import 'vodozemac_init.dart';
import 'zuno_client.dart';

final uploadProgressHttpClientProvider = Provider<UploadProgressHttpClient>((
  ref,
) {
  throw UnimplementedError(
    'uploadProgressHttpClientProvider must be overridden in ProviderScope '
    'after createMatrixClient() has run — see main.dart.',
  );
});

final matrixClientProvider = Provider<Client>((ref) {
  throw UnimplementedError(
    'matrixClientProvider must be overridden in ProviderScope after '
    'createMatrixClient() has run — see main.dart.',
  );
});

final isLoggedInProvider = StreamProvider<bool>((ref) async* {
  final client = ref.watch(matrixClientProvider);
  yield client.isLogged();
  yield* client.onLoginStateChanged.stream.map(
    (state) => state != LoginState.loggedOut,
  );
});

final signInInFlightProvider = NotifierProvider<SignInInFlight, bool>(
  SignInInFlight.new,
);

class SignInInFlight extends Notifier<bool> {
  @override
  bool build() => false;

  Future<T> during<T>(Future<T> Function() signIn) async {
    state = true;
    try {
      return await signIn();
    } finally {
      state = false;
    }
  }
}

final firstSyncProvider = FutureProvider<void>((ref) async {
  final client = ref.watch(matrixClientProvider);
  ref.watch(isLoggedInProvider);
  if (client.prevBatch != null) return;
  await client.onSyncStatus.stream.firstWhere(
    (update) => update.status == SyncStatus.finished,
  );
});

final incomingKeyVerificationProvider = StreamProvider<KeyVerification>((ref) {
  final client = ref.watch(matrixClientProvider);
  return client.onKeyVerificationRequest.stream;
});

const _connectTimeout = Duration(seconds: 10);
const _databaseFileName = 'zuno.db';

typedef StartedMatrixClient = ({
  Client client,
  UploadProgressHttpClient uploadProgressHttpClient,
});

Future<StartedMatrixClient> createMatrixClient({
  bool backgroundSync = true,
  Future<void> Function(Duration delay)? pause,
}) async {
  if (!backgroundSync) return _startBackgroundClient();
  await _holdAppLease();
  final path = await _databasePath();
  return startWithRetries(
    attempt: () => _startClient(path, backgroundSync: true),
    pause: pause,
  );
}

Future<StartedMatrixClient> startOverWithFreshStore() async {
  await _holdAppLease();
  final path = await _databasePath();
  await _discardStore(path);
  return _startClient(path, backgroundSync: true);
}

Future<ClientLease>? _appLease;

Future<ClientLease> _holdAppLease() =>
    _appLease ??= ClientLeases.instance.acquire(ClientLeaseKind.app);

@visibleForTesting
void forgetAppLeaseForTest() => _appLease = null;

Future<StartedMatrixClient> _startBackgroundClient() async {
  final lease = await ClientLeases.instance.acquire(ClientLeaseKind.background);
  try {
    return await _startClient(
      await _databasePath(),
      backgroundSync: false,
      lease: lease,
    );
  } catch (_) {
    await lease.release();
    rethrow;
  }
}

Future<String> _databasePath() async {
  final support = await getApplicationSupportDirectory();
  return p.join(support.path, _databaseFileName);
}

Future<StartedMatrixClient> _startClient(
  String path, {
  required bool backgroundSync,
  ClientLease? lease,
}) async {
  keepNoSdkLogHistory();
  final vodInitFuture = ensureVodozemacInitialized();
  final watch = Stopwatch()..start();

  ZunoClient? client;
  final uploadProgressHttpClient = UploadProgressHttpClient(
    FreshTokenHttpClient(
      IOClient(HttpClient()..connectionTimeout = _connectTimeout),
      accessToken: () => client?.accessToken,
      ensureFresh: () async {
        await client?.ensureNotSoftLoggedOut();
      },
    ),
  );

  try {
    final sqlite = await _openDatabase(path, createKey: backgroundSync);
    final exportsSessions = exportsInboundSessions(appClient: backgroundSync);
    final database = exportsSessions
        ? await openSessionExportingDatabase(sqlite)
        : await openZunoDatabase(sqlite);
    final databaseMs = watch.elapsedMilliseconds;

    final started = client = ZunoClient(
      'Zuno',
      httpClient: uploadProgressHttpClient,
      database: database,
      nativeImplementations: backgroundSync
          ? NativeImplementationsIsolate(
              compute,
              vodozemacInit: ensureVodozemacInitialized,
            )
          : NativeImplementations.dummy,
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.qrShow,
        KeyVerificationMethod.qrScan,
      },
      roomPreviewLastEvents: {
        EventTypes.Message,
        EventTypes.Encrypted,
        EventTypes.Sticker,
      },
      onSoftLogout: refreshSession,
      appClient: backgroundSync,
      lease: lease,
      keepAwake: exportsSessions ? sendKeepAwake : null,
    );
    await vodInitFuture;

    started.importantStateEvents
      ..add(callMemberEventType)
      ..add(liveLocationStateType);

    await started.restoreSession();
    if (kDebugMode) {
      debugPrint(
        'zuno/push: client timing ${backgroundSync ? 'app' : 'headless'} '
        'db=${databaseMs}ms init=${watch.elapsedMilliseconds - databaseMs}ms',
      );
    }

    if (!backgroundSync) started.backgroundSync = false;

    started.syncErrorTimeoutSec = 1;

    return (
      client: started,
      uploadProgressHttpClient: uploadProgressHttpClient,
    );
  } catch (_) {
    vodInitFuture.ignore();
    await _abandon(client, uploadProgressHttpClient);
    rethrow;
  }
}

bool exportsInboundSessions({
  required bool appClient,
  PlatformCapabilities? capabilities,
}) => appClient && (capabilities ?? ambientCapabilities).nseNotifications;

Future<void> _abandon(Client? client, UploadProgressHttpClient http) async {
  try {
    await client?.dispose(closeDatabase: false);
  } catch (error) {
    debugPrint('zuno/db: could not dispose a client that failed: $error');
  }
  http.close();
}

Future<void> _discardStore(String path) async {
  await discardDatabaseCipher();
  await sqflite.databaseFactory.deleteDatabase(path);
}

Future<sqflite.Database> _openDatabase(
  String path, {
  required bool createKey,
}) async {
  final cipher = await obtainDatabaseCipher(
    databasePath: path,
    createIfMissing: createKey,
  );

  final database = await openSharedDatabaseWithCachedKey(
    path,
    passphrase: cipher,
  );
  await _assertSqlCipherPresent(database);
  if (createKey) {
    await runBestEffort(
      () => compactDatabase(database),
      label: 'compact the database at startup',
    );
    unawaited(
      cacheDatabaseRawKey(
        path,
        passphrase: cipher,
        derive: deriveDatabaseRawKeyFast,
      ),
    );
  }
  return ambientCapabilities.atomicDatabaseBatches
      ? AtomicBatchDatabase(database)
      : database;
}

Future<void> _assertSqlCipherPresent(sqflite.Database database) async {
  final result = await database.rawQuery('PRAGMA cipher_version;');
  if (result.isEmpty || result.single.values.first == null) {
    throw StateError(
      'SQLCipher is not available — the local database would be written '
      'in plaintext. Check that sqflite_sqlcipher is linked.',
    );
  }
}
