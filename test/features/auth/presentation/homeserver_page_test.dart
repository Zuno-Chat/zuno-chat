import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/homeserver_input.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/auth/presentation/homeserver_page.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_homeserver.dart';
import '../../../helpers/pump_until.dart';

void main() {
  late ProviderContainer container;

  MockClient server({Set<String> down = const {}}) =>
      MockClient((request) async {
        if (down.contains(request.url.host)) {
          throw http.ClientException('offline');
        }
        if (request.url.path.endsWith('/versions')) {
          return http.Response(
            jsonEncode({
              'versions': ['v1.1', 'v1.5'],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);
      });

  Future<void> pumpHomeserverPage(
    WidgetTester tester, {
    http.Client? httpClient,
    bool pushed = false,
  }) async {
    final client = buildTestClient(httpClient: httpClient)
      ..homeserver = officialHomeserver;
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        homeserverProvider.overrideWith(
          () => FixedHomeserver(officialHomeserver),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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
    await pumpRealAsync(tester, rounds: 10);
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
      Uri.parse('https://example.org'),
    );
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
  });

  testWidgets('an address that is not a Matrix server says so, and is no '
      'failure to report', (tester) async {
    await pumpHomeserverPage(
      tester,
      httpClient: MockClient((_) async => http.Response('<html></html>', 404)),
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

  testWidgets('a failure that lands after the page is gone is dropped', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await pumpHomeserverPage(
      tester,
      httpClient: MockClient((_) => answer.future),
    );

    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    answer.complete(http.Response('not a homeserver', 500));
    await pumpRealAsync(tester, rounds: 5);

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
        find.text(parseHomeserverInput('not a server').error!),
        findsOneWidget,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
