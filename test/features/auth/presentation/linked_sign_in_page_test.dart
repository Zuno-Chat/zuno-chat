import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/linked_sign_in.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/auth/presentation/linked_sign_in_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_homeserver.dart';

void main() {
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
  }

  Client clientRecording(List<Map<String, Object?>> loginBodies) {
    return buildTestClient(
      httpClient: MockClient((request) async {
        loginBodies.add(jsonDecode(request.body) as Map<String, Object?>);
        return http.Response(
          jsonEncode({
            'errcode': 'M_FORBIDDEN',
            'error': 'Invalid login token',
          }),
          403,
        );
      }),
    )..homeserver = Uri.parse('https://example.org');
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required Client client,
    CodeScanner? scan,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        homeserverProvider.overrideWith(
          () => FixedHomeserver(Uri.https('example.org')),
        ),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold()),
      ),
    );
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => LinkedSignInPage(scan: scan ?? (_) async => null),
            ),
          ),
    );
    await tester.pumpAndSettle();
  }

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  testWidgets('a typed code signs in with the token and a refresh token', (
    tester,
  ) async {
    final bodies = <Map<String, Object?>>[];
    await pumpPage(tester, client: clientRecording(bodies));

    await tester.enterText(field('Code'), 'syl_ abcd efgh');
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Sign in with the code'),
    );
    await settle(tester);

    expect(bodies, hasLength(1));
    expect(bodies.single['type'], 'm.login.token');
    expect(bodies.single['token'], 'syl_abcdefgh');
    expect(bodies.single['refresh_token'], isTrue);
  });

  testWidgets('an empty code never reaches the network', (tester) async {
    final bodies = <Map<String, Object?>>[];
    await pumpPage(tester, client: clientRecording(bodies));

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Sign in with the code'),
    );
    await settle(tester);

    expect(find.text('Enter the code'), findsOneWidget);
    expect(bodies, isEmpty);
  });

  testWidgets('says the code is not valid when the server refuses it', (
    tester,
  ) async {
    await pumpPage(tester, client: clientRecording([]));

    await tester.enterText(field('Code'), 'syl_expired');
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Sign in with the code'),
    );
    await settle(tester);

    expect(find.text(invalidSignInCodeMessage), findsOneWidget);
  });

  testWidgets('a scanned Zuno code signs in with its token', (tester) async {
    final bodies = <Map<String, Object?>>[];
    const code = LinkedSignInCode(server: 'example.org', token: 'syl_scanned');
    await pumpPage(
      tester,
      client: clientRecording(bodies),
      scan: (_) async => bytesOf(code.encode()),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan code'));
    await settle(tester);

    expect(bodies.single['token'], 'syl_scanned');
  });

  testWidgets('a scanned code that is not ours is refused before any request', (
    tester,
  ) async {
    final bodies = <Map<String, Object?>>[];
    await pumpPage(
      tester,
      client: clientRecording(bodies),
      scan: (_) async => bytesOf('https://example.org/not-a-code'),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan code'));
    await settle(tester);

    expect(find.text(notASignInCodeMessage), findsOneWidget);
    expect(bodies, isEmpty);
  });

  testWidgets('a scanned code for another server is refused, naming it', (
    tester,
  ) async {
    final bodies = <Map<String, Object?>>[];
    const code = LinkedSignInCode(server: 'other.example', token: 'syl_x');
    await pumpPage(
      tester,
      client: clientRecording(bodies),
      scan: (_) async => bytesOf(code.encode()),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan code'));
    await settle(tester);

    expect(
      find.text(codeForAnotherServerMessage('other.example')),
      findsOneWidget,
    );
    expect(bodies, isEmpty);
  });

  testWidgets('a scanned code matches the server regardless of case', (
    tester,
  ) async {
    final bodies = <Map<String, Object?>>[];
    const code = LinkedSignInCode(server: 'Example.ORG', token: 'syl_case');
    await pumpPage(
      tester,
      client: clientRecording(bodies),
      scan: (_) async => bytesOf(code.encode()),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan code'));
    await settle(tester);

    expect(bodies.single['token'], 'syl_case');
  });

  testWidgets('a cancelled scan changes nothing', (tester) async {
    final bodies = <Map<String, Object?>>[];
    await pumpPage(tester, client: clientRecording(bodies));

    await tester.tap(find.widgetWithText(FilledButton, 'Scan code'));
    await settle(tester);

    expect(find.byType(LinkedSignInPage), findsOneWidget);
    expect(bodies, isEmpty);
  });
}
