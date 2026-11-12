import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/account/account_page_browser.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_sign_in_browser.dart';

class _SessionClient extends Client {
  _SessionClient({required super.onSoftLogout, this.expires = true})
    : super('test', database: FakeDatabaseApi()) {
    accessToken = 'a0';
  }

  final bool expires;

  @override
  DateTime? get accessTokenExpiresAt =>
      expires ? clock.now().add(const Duration(minutes: 5)) : null;
}

void main() {
  final page = Uri.parse('https://auth.example.org/account/?action=x');
  const notOpened =
      'Link not opened. Visit auth.example.org/account/ in a browser.';

  late int sessionChecks;
  late Client client;

  setUp(() {
    sessionChecks = 0;
    client = _SessionClient(onSoftLogout: (_) async => sessionChecks++);
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(),
        ),
      ),
    );
    return tester.element(find.byType(Scaffold));
  }

  testWidgets('opens the page in the sign-in browser and finishes when it is '
      'closed', (tester) async {
    final closed = Completer<Object?>();
    final opened = mockSignInBrowser(tester, answer: () => closed.future);
    final context = await pumpHost(tester);

    var done = false;
    unawaited(openAccountPage(context, page).then((_) => done = true));
    await tester.pump();

    expect(opened, [page.toString()]);
    expect(done, isFalse);

    closed.completeError(PlatformException(code: 'CANCELED'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('closing the page checks the session is still on', (
    tester,
  ) async {
    mockSignInBrowser(tester);
    final context = await pumpHost(tester);

    await openAccountPage(context, page);
    await tester.pumpAndSettle();

    expect(sessionChecks, 1);
  });

  testWidgets('a session whose token never expires is not checked', (
    tester,
  ) async {
    client = _SessionClient(
      onSoftLogout: (_) async => sessionChecks++,
      expires: false,
    );
    mockSignInBrowser(tester);
    final context = await pumpHost(tester);

    await openAccountPage(context, page);
    await tester.pumpAndSettle();

    expect(sessionChecks, 0);
  });

  testWidgets('a session that ended while the page was open is not checked '
      'again', (tester) async {
    client.accessToken = null;
    mockSignInBrowser(tester);
    final context = await pumpHost(tester);

    await openAccountPage(context, page);
    await tester.pumpAndSettle();

    expect(client.accessTokenExpiresAt, isNotNull);
    expect(sessionChecks, 0);
  });

  testWidgets('a page that never opened checks nothing', (tester) async {
    mockSignInBrowser(tester, answer: noSignInBrowser);
    final context = await pumpHost(tester);

    await openAccountPage(context, page);
    await tester.pumpAndSettle();

    expect(sessionChecks, 0);
  });

  testWidgets('no browser says where to go, with no report', (tester) async {
    mockSignInBrowser(tester, answer: noSignInBrowser);
    final context = await pumpHost(tester);

    final reports = await reportsDuring(() async {
      await openAccountPage(context, page);
      await tester.pumpAndSettle();
    });

    expect(find.text(notOpened), findsOneWidget);
    expect(reports, isEmpty);
  });

  testWidgets('any other failure says where to go and is reported', (
    tester,
  ) async {
    mockSignInBrowser(
      tester,
      answer: () async => throw PlatformException(code: 'EUNKNOWN'),
    );
    final context = await pumpHost(tester);

    final reports = await reportsDuring(() async {
      await openAccountPage(context, page);
      await tester.pumpAndSettle();
    });

    expect(find.text(notOpened), findsOneWidget);
    expect(reports, ['open a link']);
  });
}
