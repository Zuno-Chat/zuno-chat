import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/homeserver_input.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/server_choice.dart';
import 'package:zuno/features/auth/presentation/homeserver_page.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_homeserver.dart';
import '../../../helpers/password_server.dart';

void main() {
  late ProviderContainer container;
  late Client client;
  final zuno = ServerChoice(officialHomeserver, apiHost: officialHomeserver);

  http.Response versions() => http.Response(
    jsonEncode({
      'versions': ['v1.1', 'v1.5'],
    }),
    200,
  );

  FakeHttpClient server({
    Set<String> down = const {},
    Future<http.Response>? heldVersions,
  }) => FakeHttpClient((request) async {
    if (down.contains(request.url.host)) {
      throw http.ClientException('offline');
    }
    if (request.url.path.endsWith('/versions')) {
      return heldVersions ?? versions();
    }
    final password = passwordServerAnswer(request);
    if (password != null) return password;
    return http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);
  });

  Future<void> pumpHomeserverPage(
    WidgetTester tester, {
    http.Client? httpClient,
    bool pushed = false,
  }) async {
    client = buildTestClient(httpClient: httpClient)
      ..homeserver = officialHomeserver;
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        homeserverProvider.overrideWith(() => FixedHomeserver(zuno)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: pushed ? const Scaffold() : const HomeserverPage(),
        ),
      ),
    );
    if (pushed) {
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(builder: (_) => const HomeserverPage()),
            ),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> submit(WidgetTester tester, String server) async {
    await tester.enterText(find.byType(TextField), server);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('the address is not autocorrected and keeps its URL keyboard', (
    tester,
  ) async {
    await pumpHomeserverPage(tester);

    final server = tester.widget<TextField>(find.byType(TextField));
    expect(server.autocorrect, isFalse);
    expect(server.keyboardType, TextInputType.url);
    expect(
      server.enableSuggestions,
      isTrue,
      reason: 'off, Android swaps the URL keyboard for a password one',
    );
  });

  testWidgets(
    'starts with the current server, selected so typing replaces it',
    (tester) async {
      await pumpHomeserverPage(tester);

      final value = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .value;
      expect(value.text, 'zuno.chat');
      expect(value.selection.baseOffset, 0);
      expect(value.selection.extentOffset, 'zuno.chat'.length);
    },
  );

  testWidgets('a server that answers is taken and the screen closes', (
    tester,
  ) async {
    await pumpHomeserverPage(tester, httpClient: server(), pushed: true);

    await submit(tester, 'example.org');
    await tester.pumpAndSettle();

    expect(find.byType(HomeserverPage), findsNothing);
    expect(
      container.read(homeserverProvider).value,
      ServerChoice(
        Uri.parse('https://example.org'),
        apiHost: Uri.parse('https://example.org'),
      ),
    );
    expect(client.homeserver, Uri.parse('https://example.org'));
  });

  testWidgets('a server that does not answer is refused, and the screen '
      'stays', (tester) async {
    await pumpHomeserverPage(
      tester,
      httpClient: server(down: {'typo.example'}),
      pushed: true,
    );

    await submit(tester, 'typo.example');

    expect(find.byType(HomeserverPage), findsOneWidget);
    expect(
      find.text(
        'Cannot reach that server. Check the address and your connection.',
      ),
      findsOneWidget,
    );
    expect(container.read(homeserverProvider).value, zuno);
    expect(client.homeserver, officialHomeserver);
  });

  testWidgets('an address that is not a Matrix server says so, and is no '
      'failure to report', (tester) async {
    await pumpHomeserverPage(
      tester,
      httpClient: FakeHttpClient(
        (_) async => http.Response('<html></html>', 404),
      ),
      pushed: true,
    );

    final reports = await reportsDuring(() => submit(tester, 'blog.example'));

    expect(find.byType(HomeserverPage), findsOneWidget);
    expect(
      find.text('That address is not a server Zuno can use. Check it.'),
      findsOneWidget,
    );
    expect(reports, isEmpty);
  });

  for (final (name, limited) in <(String, http.Response Function())>[
    (
      'a rate limit',
      () => http.Response(
        jsonEncode({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too many requests',
          'retry_after_ms': 30000,
        }),
        429,
      ),
    ),
    (
      'a rate limit without Matrix JSON',
      () => http.Response(
        '<html>Too Many Requests</html>',
        429,
        headers: {'retry-after': '30'},
      ),
    ),
  ]) {
    group(name, () {
      const message = 'Too many attempts. Try again in 30 seconds.';
      late List<Uri> checks;

      FilledButton continueButton(WidgetTester tester) => tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));

      Future<void> pumpLimited(WidgetTester tester) async {
        checks = [];
        await pumpHomeserverPage(
          tester,
          httpClient: FakeHttpClient((request) async {
            if (!request.url.path.endsWith('/versions')) {
              return passwordServerAnswer(request) ??
                  http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);
            }
            checks.add(request.url);
            return limited();
          }),
        );
        await submit(tester, 'example.org');
      }

      testWidgets('holds Continue and says to wait for as long as the server '
          'said', (tester) async {
        await pumpLimited(tester);

        expect(find.text(message), findsOneWidget);
        expect(continueButton(tester).onPressed, isNull);

        await tester.pump(const Duration(seconds: 29));
        expect(continueButton(tester).onPressed, isNull);

        await tester.pump(const Duration(seconds: 1));
        expect(continueButton(tester).onPressed, isNotNull);
        expect(find.text(message), findsNothing);
      });

      testWidgets('cannot be sidestepped from the keyboard', (tester) async {
        await pumpLimited(tester);

        await tester.showKeyboard(find.byType(TextField));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(checks, hasLength(1));
        expect(find.text(message), findsOneWidget);
      });
    });
  }

  testWidgets('Back during a check leaves at once, and the check passing '
      'later changes nothing', (tester) async {
    final answer = Completer<http.Response>();
    await pumpHomeserverPage(
      tester,
      httpClient: server(heldVersions: answer.future),
      pushed: true,
    );

    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();

    expect(find.byType(HomeserverPage), findsNothing);
    expect(client.homeserver, officialHomeserver);

    answer.complete(versions());
    await tester.pumpAndSettle();

    expect(container.read(homeserverProvider).value, zuno);
    expect(client.homeserver, officialHomeserver);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a check passing while the page slides out after Back changes '
      'nothing and leaves the screen below in place', (tester) async {
    final answer = Completer<http.Response>();
    await pumpHomeserverPage(
      tester,
      httpClient: server(heldVersions: answer.future),
      pushed: true,
    );

    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump(const Duration(milliseconds: 50));

    answer.complete(versions());
    await tester.pumpAndSettle();

    expect(find.byType(HomeserverPage), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(container.read(homeserverProvider).value, zuno);
    expect(client.homeserver, officialHomeserver);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failure that lands after the page is gone is dropped', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await pumpHomeserverPage(
      tester,
      httpClient: FakeHttpClient((_) => answer.future),
    );

    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    answer.complete(http.Response('not a homeserver', 500));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('the keyboard', () {
    testWidgets('stays closed until the field is tapped', (tester) async {
      await pumpHomeserverPage(tester);
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('closes when Continue is tapped, even on a bad address', (
      tester,
    ) async {
      await pumpHomeserverPage(tester);
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);

      await submit(tester, 'not a server');

      expect(find.byType(HomeserverPage), findsOneWidget);
      expect(
        find.text(
          parseHomeserverInput(englishLocalizations, 'not a server').error!,
        ),
        findsOneWidget,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
