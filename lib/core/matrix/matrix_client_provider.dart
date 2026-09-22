import 'dart:io';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import '../calls/matrixrtc/call_member_state.dart' show callMemberEventType;
import 'database_key.dart';
import 'session_refresh.dart';
import 'upload_progress_http_client.dart';
import 'vodozemac_init.dart';
import 'zstd_response_http_client.dart';

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

final incomingKeyVerificationProvider = StreamProvider<KeyVerification>((ref) {
  final client = ref.watch(matrixClientProvider);
  return client.onKeyVerificationRequest.stream;
});

const _connectTimeout = Duration(seconds: 10);

Future<({Client client, UploadProgressHttpClient uploadProgressHttpClient})>
createMatrixClient({bool backgroundSync = true}) async {
  final vodInitFuture = ensureVodozemacInitialized();
  final watch = Stopwatch()..start();

  final uploadProgressHttpClient = UploadProgressHttpClient(
    ZstdResponseHttpClient(
      IOClient(HttpClient()..connectionTimeout = _connectTimeout),
    ),
  );

  final database = await MatrixSdkDatabase.init(
    'zuno',
    database: kIsWeb ? null : await _openDatabase(),
  );
  final databaseMs = watch.elapsedMilliseconds;

  final client = Client(
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
  );
  await vodInitFuture;

  client.importantStateEvents.add(callMemberEventType);

  await client.init(waitForFirstSync: false);
  if (kDebugMode) {
    debugPrint(
      'zuno/push: client timing ${backgroundSync ? 'app' : 'headless'} '
      'db=${databaseMs}ms init=${watch.elapsedMilliseconds - databaseMs}ms',
    );
  }

  if (!backgroundSync) client.backgroundSync = false;

  client.syncErrorTimeoutSec = 1;

  return (client: client, uploadProgressHttpClient: uploadProgressHttpClient);
}

Future<sqflite.Database> _openDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final path = p.join(directory.path, 'zuno.db');
  final cipher = await obtainDatabaseCipher();

  final database = await sqflite.openDatabase(path, password: cipher);
  await _assertSqlCipherPresent(database);
  return database;
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
