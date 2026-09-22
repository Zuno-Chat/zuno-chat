import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/auth/presentation/register_page.dart';
import 'package:zuno/features/auth/presentation/registration_code_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Future<List<http.Request>> pumpCodePage(
    WidgetTester tester, {
    http.Response Function()? respond,
  }) async {
    final requests = <http.Request>[];
    final client = buildTestClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond?.call() ?? http.Response('{}', 202);
      }),
    )..homeserver = Uri.parse('https://example.org');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: RegistrationCodePage()),
      ),
    );
    return requests;
  }

  Future<void> send(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField), email);
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('a sent code leads to the account form', (tester) async {
    await pumpCodePage(tester);

    await send(tester, 'alex@example.org');

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(find.text('Sign-up code'), findsOneWidget);
  });

  testWidgets('an address that cannot be one never reaches the network', (
    tester,
  ) async {
    final requests = await pumpCodePage(tester);

    await send(tester, 'alex');

    expect(find.byType(RegisterPage), findsNothing);
    expect(
      find.text('That email address does not look right.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
  });

  testWidgets('a rate-limited request says to wait', (tester) async {
    await pumpCodePage(
      tester,
      respond: () => http.Response(jsonEncode({'error': 'slow down'}), 429),
    );

    await send(tester, 'alex@example.org');

    expect(
      find.text('Too many code requests. Try again later.'),
      findsOneWidget,
    );
    expect(find.byType(RegisterPage), findsNothing);
  });

  testWidgets('a failure nobody planned for leaves the form usable', (
    tester,
  ) async {
    await pumpCodePage(tester, respond: () => throw StateError('boom'));

    await send(tester, 'alex@example.org');

    expect(find.text('Zuno could not send a code. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send code'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('the address is not autocorrected and keeps its @ keyboard', (
    tester,
  ) async {
    await pumpCodePage(tester);

    final email = tester.widget<TextField>(find.byType(TextField));
    expect(email.autocorrect, isFalse);
    expect(email.keyboardType, TextInputType.emailAddress);
    expect(
      email.enableSuggestions,
      isTrue,
      reason: 'off, Android swaps the email keyboard for a password one',
    );
  });

  testWidgets('skipping goes straight to the account form', (tester) async {
    await pumpCodePage(tester);

    await tester.tap(find.widgetWithText(TextButton, 'I already have a code'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(find.text('Sign-up code'), findsOneWidget);
  });

  group('the keyboard', () {
    testWidgets('stays closed until the field is tapped', (tester) async {
      await pumpCodePage(tester);
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('closes when Send code is tapped, even on a bad address', (
      tester,
    ) async {
      await pumpCodePage(tester);
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);

      await send(tester, 'alex');

      expect(find.byType(RegisterPage), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('does not come back after the account form is left', (
      tester,
    ) async {
      await pumpCodePage(tester);
      await tester.showKeyboard(find.byType(TextField));

      await tester.tap(
        find.widgetWithText(TextButton, 'I already have a code'),
      );
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationCodePage), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
