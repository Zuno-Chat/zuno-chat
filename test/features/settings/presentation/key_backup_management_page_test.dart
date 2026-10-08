import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/settings/presentation/key_backup_management_page.dart';

import '../../../helpers/fake_encryption.dart';

GetRoomKeysVersionCurrentResponse _backup({int count = 42}) =>
    GetRoomKeysVersionCurrentResponse.fromJson({
      'algorithm': 'm.megolm_backup.v1.curve25519-aes-sha2',
      'auth_data': {'public_key': 'abc'},
      'count': count,
      'etag': '1',
      'version': '7',
    });

class _BackupClient extends EncryptedTestClient {
  _BackupClient() : super(userId: '@alice:example.org', testDeviceId: 'HERE');

  GetRoomKeysVersionCurrentResponse? backup = _backup();
  Object? readError;
  Completer<void>? readGate;
  int reads = 0;
  final deleted = <String>[];
  Object? deleteError;
  Completer<void>? deleteGate;

  @override
  Future<GetRoomKeysVersionCurrentResponse> getRoomKeysVersionCurrent() async {
    reads++;
    await readGate?.future;
    final error = readError;
    if (error != null) throw error;
    return backup ??
        (throw MatrixException.fromJson({
          'errcode': 'M_NOT_FOUND',
          'error': 'No current backup version',
        }));
  }

  @override
  Future<void> deleteRoomKeysVersion(String version) async {
    await deleteGate?.future;
    final error = deleteError;
    if (error != null) throw error;
    deleted.add(version);
    backup = null;
  }
}

void main() {
  late _BackupClient client;

  setUp(() => client = _BackupClient());

  Future<void> pumpPage(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: KeyBackupManagementPage()),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  String? subtitleOf(WidgetTester tester, String title) =>
      (tester.widget<ListTile>(find.widgetWithText(ListTile, title)).subtitle
              as Text?)
          ?.data;

  Finder deleteRow() => find.widgetWithText(ListTile, 'Delete key backup');

  testWidgets('shows a spinner until the backup is read', (tester) async {
    client.readGate = Completer();
    await pumpPage(tester, settle: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    client.readGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('without a backup it says so', (tester) async {
    client.backup = null;
    await pumpPage(tester);

    expect(find.text('No key backup set up on this account.'), findsOneWidget);
    expect(deleteRow(), findsNothing);
  });

  testWidgets('lists the backup details', (tester) async {
    await pumpPage(tester);

    expect(subtitleOf(tester, 'Keys backed up'), '42');
    expect(subtitleOf(tester, 'Version'), '7');
    expect(
      subtitleOf(tester, 'Algorithm'),
      'm.megolm_backup.v1.curve25519-aes-sha2',
    );
  });

  testWidgets('says when this device cannot restore from it', (tester) async {
    await pumpPage(tester);

    expect(
      subtitleOf(tester, 'Status'),
      'Active, but this device cannot restore from it (set up Secure backup)',
    );
  });

  testWidgets('says when this device can restore from it', (tester) async {
    client
      ..setUpRecovery()
      ..unlockRecovery();
    await pumpPage(tester);

    expect(
      subtitleOf(tester, 'Status'),
      'Active — this device can restore from it',
    );
  });

  testWidgets('a failed read says so instead of spinning forever', (
    tester,
  ) async {
    client.readError = Exception('offline');
    await pumpPage(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Could not load the key backup. Pull down to try again.'),
      findsOneWidget,
    );
  });

  testWidgets('pulling down reads it again and keeps the details on screen', (
    tester,
  ) async {
    await pumpPage(tester);
    client
      ..backup = _backup(count: 43)
      ..readGate = Completer();

    await tester.fling(find.text('Status'), const Offset(0, 500), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(client.reads, 2);
    expect(find.text('Keys backed up'), findsOneWidget);

    client.readGate!.complete();
    await tester.pumpAndSettle();

    expect(subtitleOf(tester, 'Keys backed up'), '43');
  });

  group('deleting', () {
    Future<void> tapDelete(WidgetTester tester) async {
      await tester.tap(deleteRow());
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, and Cancel keeps the backup', (tester) async {
      await pumpPage(tester);

      await tapDelete(tester);
      expect(find.text('Delete key backup?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(client.deleted, isEmpty);
      expect(subtitleOf(tester, 'Version'), '7');
    });

    testWidgets('deletes that version and shows the result', (tester) async {
      await pumpPage(tester);

      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(client.deleted, ['7']);
      expect(
        find.text('No key backup set up on this account.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a spinner meanwhile and takes no second tap', (
      tester,
    ) async {
      client.deleteGate = Completer();
      await pumpPage(tester);

      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(
          of: deleteRow(),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(deleteRow()).onTap, isNull);

      client.deleteGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a refusal says so, without the server error, and keeps '
        'the backup', (tester) async {
      client.deleteError = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Not allowed',
      });
      await pumpPage(tester);

      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Could not delete the key backup.'), findsOneWidget);
      expect(find.textContaining('M_FORBIDDEN'), findsNothing);
      expect(find.textContaining('Not allowed'), findsNothing);
      expect(tester.widget<ListTile>(deleteRow()).onTap, isNotNull);
    });

    testWidgets('deleting while offline says to check the connection', (
      tester,
    ) async {
      client.deleteError = http.ClientException('Failed host lookup');
      await pumpPage(tester);

      await tapDelete(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not delete the key backup. Check your connection and try '
          'again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(client.deleted, isEmpty);
    });

    testWidgets('a failed read afterwards is not reported as a failed delete', (
      tester,
    ) async {
      await pumpPage(tester);

      await tapDelete(tester);
      client.readError = Exception('offline');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(client.deleted, ['7']);
      expect(find.textContaining('Could not delete'), findsNothing);
      expect(
        find.text('Could not load the key backup. Pull down to try again.'),
        findsOneWidget,
      );
    });
  });
}
