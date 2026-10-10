import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/navigation/zuno_links.dart';
import 'package:zuno/features/auth/presentation/register_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_homeserver.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/pump_until.dart';

const _tokenThenDummyFlows = [
  {
    'stages': ['m.login.registration_token', 'm.login.dummy'],
  },
];

void main() {
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  Future<void> pumpRegisterPage(
    WidgetTester tester, {
    http.Client? httpClient,
    bool requiresCode = false,
    String? email,
    String homeserver = 'https://example.org',
    String? chosenServerName,
    UrlOpener openUrl = openExternally,
    bool pushed = false,
  }) async {
    final container = await containerWithPreferences(
      {},
      overrides: [
        matrixClientProvider.overrideWithValue(
          buildTestClient(httpClient: httpClient)
            ..homeserver = Uri.parse(homeserver),
        ),
        homeserverProvider.overrideWith(
          () => FixedHomeserver(
            Uri.https(chosenServerName ?? Uri.parse(homeserver).host),
          ),
        ),
      ],
    );
    final page = RegisterPage(
      requiresCode: requiresCode,
      email: email,
      openUrl: openUrl,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: pushed ? const Scaffold() : page),
      ),
    );
    if (pushed) {
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(MaterialPageRoute<void>(builder: (_) => page)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String username = 'alice',
    String password = 'correct horse battery staple',
    String? code,
    int turns = 1,
  }) async {
    if (code != null) await tester.enterText(field('Sign-up code'), code);
    await tester.enterText(field('Username'), username);
    await tester.enterText(field('Password'), password);
    await tester.enterText(field('Confirm password'), password);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await pumpRealAsync(tester, rounds: turns);
  }

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  FilledButton createButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Create account'),
  );

  const termsLine =
      'Creating an account means you agree to the terms and the privacy '
      'policy.';

  testWidgets('on another server there are no terms of Zuno to accept', (
    tester,
  ) async {
    await pumpRegisterPage(tester, chosenServerName: 'example.org');

    expect(find.text(termsLine), findsNothing);
    expect(find.text('Terms'), findsNothing);
    expect(find.text('Privacy policy'), findsNothing);
  });

  testWidgets('on zuno.chat, creating an account accepts the terms, and Terms '
      'and Privacy policy open their pages on the website', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <Uri>[];
    await pumpRegisterPage(
      tester,
      chosenServerName: 'zuno.chat',
      openUrl: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    expect(find.text(termsLine), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Terms'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Privacy policy'));
    await tester.pump();

    expect(opened, [
      Uri.parse('https://zuno.chat/terms'),
      Uri.parse('https://zuno.chat/privacy'),
    ]);
  });

  testWidgets('no code field unless the server asks for one', (tester) async {
    await pumpRegisterPage(tester);

    expect(find.text('Sign-up code'), findsNothing);
  });

  testWidgets('the code field uppercases what is typed', (tester) async {
    await pumpRegisterPage(tester, requiresCode: true);

    final code = field('Sign-up code');
    await tester.enterText(code, 'ab3io1');

    expect(tester.widget<TextField>(code).controller?.text, 'AB3');
  });

  testWidgets('a refused code says so and offers a new one', (tester) async {
    useTallScreen(tester);
    final responses = [
      http.Response(
        jsonEncode({
          'session': 'uia1',
          'completed': <String>[],
          'errcode': 'M_MISSING_PARAM',
          'error': 'Missing UIA session',
          'flows': _tokenThenDummyFlows,
        }),
        401,
      ),
      http.Response(
        jsonEncode({
          'session': 'uia1',
          'completed': <String>[],
          'errcode': 'M_UNAUTHORIZED',
          'error': 'Invalid registration token',
          'flows': _tokenThenDummyFlows,
        }),
        401,
      ),
    ];
    var answered = 0;
    await pumpRegisterPage(
      tester,
      httpClient: MockClient((_) async => responses[answered++]),
      requiresCode: true,
    );

    await fillAndSubmit(tester, code: 'ABCDEFGH23', turns: 4);

    expect(find.text('That code is not valid or has expired.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Send a new code'), findsOneWidget);
  });

  testWidgets('the emailed address is named on the form', (tester) async {
    await pumpRegisterPage(
      tester,
      requiresCode: true,
      email: 'alex@example.org',
    );

    expect(
      find.text(
        'Check alex@example.org for your code. It expires in 24 hours.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('names the server you asked for, not the API host behind it', (
    tester,
  ) async {
    await pumpRegisterPage(
      tester,
      homeserver: 'https://matrix.example.org',
      chosenServerName: 'zuno.chat',
    );

    expect(find.text('Your account lives on zuno.chat.'), findsOneWidget);
  });

  testWidgets('nothing typed here is learned by the keyboard', (tester) async {
    await pumpRegisterPage(tester, requiresCode: true);

    for (final label in [
      'Sign-up code',
      'Username',
      'Password',
      'Confirm password',
    ]) {
      final input = tester.widget<TextField>(field(label));
      expect(input.autocorrect, isFalse, reason: label);
      expect(input.enableSuggestions, isFalse, reason: label);
    }
  });

  testWidgets('a generated password can fill the confirmation too', (
    tester,
  ) async {
    await pumpRegisterPage(tester);

    expect(
      tester.widget<TextField>(field('Confirm password')).autofillHints,
      contains(AutofillHints.newPassword),
    );
  });

  testWidgets('one toggle shows both passwords', (tester) async {
    await pumpRegisterPage(tester);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(tester.widget<TextField>(field('Password')).obscureText, isFalse);
    expect(
      tester.widget<TextField>(field('Confirm password')).obscureText,
      isFalse,
    );
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('next from the password lands on its confirmation', (
    tester,
  ) async {
    await pumpRegisterPage(tester);

    await tester.showKeyboard(field('Password'));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final confirm = tester.widget<EditableText>(
      find.descendant(
        of: field('Confirm password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(confirm.focusNode.hasFocus, isTrue);
  });

  testWidgets('a username too long for this server is caught here', (
    tester,
  ) async {
    useTallScreen(tester);
    var requests = 0;
    await pumpRegisterPage(
      tester,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
      chosenServerName: 'zuno.chat',
    );

    await fillAndSubmit(tester, username: 'a' * 245);

    expect(find.text('That username is too long'), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('a rate limit holds the button for as long as the server said', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpRegisterPage(
      tester,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Too many requests',
            'retry_after_ms': 5000,
          }),
          429,
        ),
      ),
    );

    await fillAndSubmit(tester);

    expect(
      find.text('Too many attempts. Try again in 5 seconds.'),
      findsOneWidget,
    );
    expect(createButton(tester).onPressed, isNull);

    await tester.enterText(field('Username'), 'alice2');
    await tester.pump();
    expect(
      find.text('Too many attempts. Try again in 5 seconds.'),
      findsOneWidget,
      reason: 'a disabled button with no explanation left on screen',
    );

    await tester.pump(const Duration(seconds: 5));
    expect(createButton(tester).onPressed, isNotNull);
    expect(find.textContaining('Too many attempts'), findsNothing);
  });

  testWidgets('a refusal that lands after the page is left is dropped', (
    tester,
  ) async {
    useTallScreen(tester);
    final answer = Completer<http.Response>();
    await pumpRegisterPage(
      tester,
      httpClient: MockClient((_) => answer.future),
    );

    await fillAndSubmit(tester, turns: 0);
    await tester.pumpWidget(const SizedBox());

    answer.complete(http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('holds the app on the sign-up screens until the account is '
      'made', (tester) async {
    useTallScreen(tester);
    final answer = Completer<http.Response>();
    await pumpRegisterPage(
      tester,
      httpClient: MockClient((_) => answer.future),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RegisterPage)),
    );

    await fillAndSubmit(tester, turns: 0);
    await tester.pump();

    expect(container.read(signInInFlightProvider), isTrue);

    answer.complete(http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403));
    await pumpRealAsync(tester, rounds: 3);

    expect(container.read(signInInFlightProvider), isFalse);
  });

  testWidgets('back stays put while the account is being created', (
    tester,
  ) async {
    useTallScreen(tester);
    final answer = Completer<http.Response>();
    await pumpRegisterPage(
      tester,
      httpClient: MockClient((_) => answer.future),
      pushed: true,
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    await fillAndSubmit(tester, turns: 0);
    await tester.pump();
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsOneWidget);

    answer.complete(http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403));
    await pumpRealAsync(tester, rounds: 3);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsNothing);
  });

  group('an interrupted sign-up', () {
    Future<List<Map<String, Object?>>> pumpInterrupted(
      WidgetTester tester,
    ) async {
      useTallScreen(tester);
      final bodies = <Map<String, Object?>>[];
      await pumpRegisterPage(
        tester,
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, Object?>);
          return switch (bodies.length) {
            1 => http.Response(
              jsonEncode({
                'session': 'uia1',
                'completed': ['m.login.registration_token'],
                'flows': _tokenThenDummyFlows,
              }),
              401,
            ),
            2 => throw http.ClientException('connection lost'),
            _ => http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403),
          };
        }),
        requiresCode: true,
      );
      await fillAndSubmit(tester, code: 'ABCDEFGH23', turns: 3);
      expect(bodies, hasLength(2));
      return bodies;
    }

    testWidgets('picks its session back up on the next try', (tester) async {
      final bodies = await pumpInterrupted(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(bodies[2]['auth'], {
        'type': 'm.login.registration_token',
        'token': 'ABCDEFGH23',
        'session': 'uia1',
      });
    });

    testWidgets('starts over when the password changed in between', (
      tester,
    ) async {
      final bodies = await pumpInterrupted(tester);

      await fillAndSubmit(
        tester,
        password: 'another horse battery staple',
        code: 'ABCDEFGH23',
      );

      expect(bodies[2]['auth'], {
        'type': 'm.login.registration_token',
        'token': 'ABCDEFGH23',
      });
    });
  });

  group('the keyboard', () {
    for (final (form, requiresCode) in [
      ('the form', false),
      ('the form that asks for a code', true),
    ]) {
      testWidgets('stays closed on $form until a field is tapped', (
        tester,
      ) async {
        await pumpRegisterPage(tester, requiresCode: requiresCode);
        await tester.pump();

        expect(tester.testTextInput.isVisible, isFalse);
      });
    }

    testWidgets('closes when Create account is tapped, even on a bad form', (
      tester,
    ) async {
      await pumpRegisterPage(tester);
      await tester.enterText(field('Password'), 'correct horse battery');
      await tester.showKeyboard(field('Confirm password'));
      expect(tester.testTextInput.isVisible, isTrue);

      final createAccount = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(createAccount);
      await tester.tap(createAccount);
      await tester.pump();

      expect(find.text('Choose a username'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
