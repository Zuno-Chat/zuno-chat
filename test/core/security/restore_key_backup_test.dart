import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zuno/core/security/restore_key_backup.dart';

import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  test(
    'reports failure, without throwing, when there is no encryption',
    () async {
      final client = buildTestClient();
      expect(client.encryption, isNull);

      await expectLater(restoreKeyBackupFromRecovery(client), completes);
      expect(await restoreKeyBackupFromRecovery(client), isFalse);
    },
  );

  test(
    'a homeserver that has no key backup is a failure, not a crash',
    () async {
      final client = buildTestClient(userId: '@a:x');

      await expectLater(restoreKeyBackupFromRecovery(client), completes);
      expect(await restoreKeyBackupFromRecovery(client), isFalse);
    },
  );

  group('with encryption', () {
    late List<String> requested;

    EncryptedTestClient clientAnswering(bool hasBackup) {
      requested = [];
      final client = EncryptedTestClient(
        userId: '@me:example.org',
        httpClient: MockClient((request) async {
          requested.add(request.url.path);
          if (!hasBackup) {
            return http.Response(
              jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'No backup'}),
              404,
            );
          }
          if (request.url.path.endsWith('/room_keys/version')) {
            return http.Response(
              jsonEncode({
                'algorithm': 'm.megolm_backup.v1.curve25519-aes-sha2',
                'auth_data': {'public_key': 'key', 'signatures': {}},
                'count': 0,
                'etag': '0',
                'version': '1',
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'rooms': {}}), 200);
        }),
      );
      client.homeserver = Uri.parse('https://example.org');
      client.bearerToken = 'token';
      return client;
    }

    test('reads every room key from the backup', () async {
      final client = clientAnswering(true);

      expect(await restoreKeyBackupFromRecovery(client), isTrue);
      expect(requested, contains(endsWith('/room_keys/keys')));
    });

    test('a server without a backup is a failure, not a crash', () async {
      final client = clientAnswering(false);

      expect(await restoreKeyBackupFromRecovery(client), isFalse);
      expect(requested, contains(endsWith('/room_keys/version')));
    });
  });
}
