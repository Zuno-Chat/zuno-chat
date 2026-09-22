import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/settings/presentation/temporary_session_token_tile.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Client clientAnswering(http.Response Function(http.Request request) answer) {
    return buildTestClient(
      userId: '@alice:example.org',
      httpClient: MockClient((request) async => answer(request)),
    )..homeserver = Uri.parse('https://example.org');
  }

  http.Response granted() => http.Response(
    jsonEncode({
      'access_token': 'syt_token',
      'device_id': 'NEWDEVICE',
      'user_id': '@alice:example.org',
    }),
    200,
  );

  http.Response forbidden() => http.Response(
    jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'Invalid password'}),
    403,
  );

  test('signs in as the current user without a refresh token', () async {
    late http.Request sent;
    final client = clientAnswering((request) {
      sent = request;
      return granted();
    });

    final session = await requestUnrefreshableSessionToken(client, 'hunter2');

    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(sent.url.path, '/_matrix/client/v3/login');
    expect(body['refresh_token'], false);
    expect(body['password'], 'hunter2');
    expect(body['identifier'], {
      'type': 'm.id.user',
      'user': '@alice:example.org',
    });
    expect(
      body['initial_device_display_name'],
      temporarySessionTokenDeviceName,
    );
    expect(session.accessToken, 'syt_token');
    expect(session.refreshToken, isNull);
  });

  test('leaves the app session untouched', () async {
    final client = clientAnswering((_) => granted());

    await requestUnrefreshableSessionToken(client, 'hunter2');

    expect(client.accessToken, isNull);
  });

  test('a wrong password throws', () async {
    final client = clientAnswering((_) => forbidden());

    expect(
      requestUnrefreshableSessionToken(client, 'nope'),
      throwsA(isA<MatrixException>()),
    );
  });

  group('dialog', () {
    Future<void> openDialog(WidgetTester tester, Client client) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [matrixClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(children: const [TemporarySessionTokenTile()]),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Get a session token'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the token once the password is accepted', (
      tester,
    ) async {
      await openDialog(tester, clientAnswering((_) => granted()));

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.text('Get token'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.text('syt_token'), findsOneWidget);
      expect(find.text('Session ID: NEWDEVICE'), findsOneWidget);
    });

    testWidgets('a wrong password shows the error and no token', (
      tester,
    ) async {
      await openDialog(tester, clientAnswering((_) => forbidden()));

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Get token'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.text('Wrong username or password'), findsOneWidget);
      expect(find.text('Session token'), findsNothing);
    });
  });
}
