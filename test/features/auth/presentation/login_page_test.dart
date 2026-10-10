import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/features/auth/presentation/auth_scaffold.dart';
import 'package:zuno/features/auth/presentation/homeserver_page.dart';
import 'package:zuno/features/auth/presentation/linked_sign_in_page.dart';
import 'package:zuno/features/auth/presentation/login_page.dart';
import 'package:zuno/features/auth/presentation/register_page.dart';
import 'package:zuno/features/auth/presentation/registration_code_page.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_homeserver.dart';
import '../../../helpers/preferences_container.dart';

void main() {
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  TextField fieldLabelled(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label));

  Future<void> pumpLoginPage(
    WidgetTester tester, {
    RegistrationSupport support = const RegistrationSupport(
      RegistrationAvailability.disabled,
    ),
    Client? client,
    String homeserver = 'https://example.org',
    String? chosenServerName,
    bool pushed = false,
    Map<String, Object> preferences = const {},
  }) async {
    final container = await containerWithPreferences(
      preferences,
      overrides: [
        matrixClientProvider.overrideWithValue(
          (client ?? buildTestClient())..homeserver = Uri.parse(homeserver),
        ),
        registrationSupportProvider.overrideWith((ref) async => support),
        homeserverProvider.overrideWith(
          () => FixedHomeserver(
            Uri.https(chosenServerName ?? Uri.parse(homeserver).host),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: pushed ? const Scaffold() : const LoginPage()),
      ),
    );
    if (pushed) {
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(MaterialPageRoute<void>(builder: (_) => const LoginPage())),
      );
    }
    await tester.pumpAndSettle();
  }

  FilledButton signInButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'));

  Future<void> signIn(
    WidgetTester tester, {
    String username = 'alice',
    String password = 'correct horse battery staple',
  }) async {
    await tester.enterText(field('Username'), username);
    await tester.enterText(field('Password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('the fields advertise a username and a password, and only the '
      'password is obscured', (tester) async {
    await pumpLoginPage(tester);

    final username = fieldLabelled(tester, 'Username');
    final password = fieldLabelled(tester, 'Password');

    expect(username.autofillHints, [AutofillHints.username]);
    expect(username.obscureText, isFalse);
    expect(password.autofillHints, [AutofillHints.password]);
    expect(password.obscureText, isTrue);
  });

  testWidgets('both fields sit inside a single shared AutofillGroup', (
    tester,
  ) async {
    await pumpLoginPage(tester);

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AutofillGroup),
        matching: find.byType(TextField),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('enter advances from username and submits from password', (
    tester,
  ) async {
    await pumpLoginPage(tester);

    expect(
      fieldLabelled(tester, 'Username').textInputAction,
      TextInputAction.next,
    );
    expect(
      fieldLabelled(tester, 'Password').textInputAction,
      TextInputAction.done,
    );
  });

  testWidgets('the form is on the card; Create account and the server sit '
      'under it', (tester) async {
    await pumpLoginPage(
      tester,
      support: const RegistrationSupport(RegistrationAvailability.available),
      pushed: true,
    );

    Finder inCard(Finder finder) =>
        find.descendant(of: find.byKey(authCardKey), matching: finder);

    expect(inCard(field('Username')), findsOneWidget);
    expect(
      inCard(find.widgetWithText(FilledButton, 'Sign in')),
      findsOneWidget,
    );
    for (final under in [
      find.widgetWithText(OutlinedButton, 'Create account'),
      find.widgetWithText(TextButton, 'Change'),
    ]) {
      expect(under, findsOneWidget);
      expect(inCard(under), findsNothing);
    }
  });

  testWidgets('offers nothing for a registration flow it cannot complete', (
    tester,
  ) async {
    await pumpLoginPage(
      tester,
      support: const RegistrationSupport(
        RegistrationAvailability.unsupportedFlow,
      ),
    );

    expect(find.text('Create account'), findsNothing);
    expect(find.textContaining('web'), findsNothing);
    expect(find.textContaining('extra steps'), findsNothing);
  });

  testWidgets('asks the homeserver for a refresh token on login', (
    tester,
  ) async {
    Map<String, Object?>? loginBody;
    final client = buildTestClient(
      httpClient: MockClient((request) async {
        loginBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403);
      }),
    );
    await pumpLoginPage(tester, client: client);

    await signIn(tester);

    expect(loginBody?['refresh_token'], isTrue);
  });

  testWidgets('a server that wants a code asks for the address first', (
    tester,
  ) async {
    await pumpLoginPage(
      tester,
      support: const RegistrationSupport(
        RegistrationAvailability.available,
        requiresRegistrationToken: true,
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(RegistrationCodePage), findsOneWidget);
  });

  testWidgets('a server that wants no code goes straight to the form', (
    tester,
  ) async {
    await pumpLoginPage(
      tester,
      support: const RegistrationSupport(RegistrationAvailability.available),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(find.byType(RegistrationCodePage), findsNothing);
  });

  testWidgets('the username field lowercases what is typed, and still takes '
      'a full user ID', (tester) async {
    await pumpLoginPage(tester);

    await tester.enterText(field('Username'), '@Alice:My-Server.org');

    expect(
      fieldLabelled(tester, 'Username').controller?.text,
      '@alice:my-server.org',
    );
  });

  testWidgets('names the server you asked for, not the API host behind it', (
    tester,
  ) async {
    await pumpLoginPage(
      tester,
      homeserver: 'https://matrix.example.org',
      chosenServerName: 'zuno.chat',
    );

    expect(find.text('zuno.chat'), findsOneWidget);
    expect(find.text('matrix.example.org'), findsNothing);
  });

  testWidgets('Change opens the server screen, even on the default', (
    tester,
  ) async {
    await pumpLoginPage(tester, chosenServerName: 'zuno.chat');

    await tester.tap(find.widgetWithText(TextButton, 'Change'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeserverPage), findsOneWidget);
  });

  testWidgets('offers signing in with a code from the other device', (
    tester,
  ) async {
    await pumpLoginPage(tester);

    final link = find.widgetWithText(
      TextButton,
      'Sign in with your other device',
    );
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byType(LinkedSignInPage), findsOneWidget);
  });

  testWidgets('empty fields never reach the network', (tester) async {
    var requests = 0;
    final client = buildTestClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    await pumpLoginPage(tester, client: client);

    await signIn(tester, username: '', password: '');
    expect(find.text('Enter your username'), findsOneWidget);

    await signIn(tester, password: '');
    expect(find.text('Enter your password'), findsOneWidget);

    expect(requests, 0);
  });

  group('a rate limit', () {
    Future<List<http.Request>> pumpLimited(WidgetTester tester) async {
      final requests = <http.Request>[];
      final client = buildTestClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'errcode': 'M_LIMIT_EXCEEDED',
              'error': 'Too many requests',
              'retry_after_ms': 30000,
            }),
            429,
          );
        }),
      );
      await pumpLoginPage(tester, client: client);
      await signIn(tester);
      return requests;
    }

    const message = 'Too many attempts. Try again in 30 seconds.';

    testWidgets('holds the button and says to wait for as long as the server '
        'said', (tester) async {
      await pumpLimited(tester);

      expect(find.text(message), findsOneWidget);
      expect(signInButton(tester).onPressed, isNull);

      await tester.pump(const Duration(seconds: 29));
      expect(signInButton(tester).onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(signInButton(tester).onPressed, isNotNull);
      expect(find.text(message), findsNothing);
    });

    testWidgets('cannot be sidestepped from the keyboard', (tester) async {
      final requests = await pumpLimited(tester);

      await tester.showKeyboard(field('Password'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(requests, hasLength(1));
    });
  });

  testWidgets('holds the app on this screen until the sign-in returns', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await pumpLoginPage(
      tester,
      client: buildTestClient(httpClient: MockClient((_) => answer.future)),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginPage)),
    );

    await tester.enterText(field('Username'), 'alice');
    await tester.enterText(field('Password'), 'correct horse battery staple');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(container.read(signInInFlightProvider), isTrue);

    answer.complete(http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(container.read(signInInFlightProvider), isFalse);
  });

  testWidgets('a refusal that lands after the page is left is dropped', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    final client = buildTestClient(
      httpClient: MockClient((_) => answer.future),
    );
    await pumpLoginPage(tester, client: client, pushed: true);

    await tester.enterText(field('Username'), 'alice');
    await tester.enterText(field('Password'), 'correct horse battery staple');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    answer.complete(http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing typed here is learned by the keyboard', (tester) async {
    await pumpLoginPage(tester);

    for (final label in ['Username', 'Password']) {
      expect(fieldLabelled(tester, label).autocorrect, isFalse, reason: label);
      expect(
        fieldLabelled(tester, label).enableSuggestions,
        isFalse,
        reason: label,
      );
    }
  });

  testWidgets('the password can be shown, and stays out of the keyboard', (
    tester,
  ) async {
    await pumpLoginPage(tester);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    final password = fieldLabelled(tester, 'Password');
    expect(password.obscureText, isFalse);
    expect(password.enableSuggestions, isFalse);
    expect(password.autocorrect, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();

    expect(fieldLabelled(tester, 'Password').obscureText, isTrue);
  });

  testWidgets('a hidden password reaches the keyboard as it always did', (
    tester,
  ) async {
    await pumpLoginPage(tester);

    expect(fieldLabelled(tester, 'Password').keyboardType, TextInputType.text);
  });

  testWidgets('a shown password blocks screenshots until it is hidden', (
    tester,
  ) async {
    final native = installFakeCallsChannel();
    await pumpLoginPage(
      tester,
      preferences: {'settings.prevent_screenshots': false},
    );

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(native.screenshotBlocking, [true]);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(native.screenshotBlocking, [true, false]);
  });

  testWidgets('hiding never lifts the block that is on by default', (
    tester,
  ) async {
    final native = installFakeCallsChannel();
    await pumpLoginPage(tester);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();

    expect(native.screenshotBlocking, [true, true]);
  });

  testWidgets('leaving with the password shown restores screenshots', (
    tester,
  ) async {
    final native = installFakeCallsChannel();
    await pumpLoginPage(
      tester,
      pushed: true,
      preferences: {'settings.prevent_screenshots': false},
    );

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(native.screenshotBlocking, [true, false]);
  });

  group('the keyboard', () {
    testWidgets('stays closed until a field is tapped', (tester) async {
      await pumpLoginPage(tester);

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('closes when Sign in is tapped', (tester) async {
      final client = buildTestClient(
        httpClient: MockClient((_) async => http.Response('{}', 500)),
      );
      await pumpLoginPage(tester, client: client);
      await tester.showKeyboard(field('Username'));
      expect(tester.testTextInput.isVisible, isTrue);

      await signIn(tester);

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('closes even when a field is left empty', (tester) async {
      await pumpLoginPage(tester);
      await tester.showKeyboard(field('Password'));
      expect(tester.testTextInput.isVisible, isTrue);

      await signIn(tester, username: '');

      expect(find.text('Enter your username'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('does not come back after visiting the server screen', (
      tester,
    ) async {
      await pumpLoginPage(tester, chosenServerName: 'zuno.chat');
      await tester.showKeyboard(field('Username'));

      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
