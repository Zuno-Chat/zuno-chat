import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/account/account_page_browser.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_sign_in_browser.dart';

void main() {
  final page = Uri.parse('https://auth.example.org/account/?action=x');
  const notOpened =
      'Link not opened. Visit auth.example.org/account/ in a browser.';

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
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
