import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/settings/presentation/delete_account_tile.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Future<void> pump(WidgetTester tester, {Client? client}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (client != null) matrixClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Scaffold(body: ListView(children: const [DeleteAccountTile()])),
        ),
      ),
    );
  }

  testWidgets('offers Delete account', (tester) async {
    await pump(tester);

    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('tapping warns before anything else', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('nobody can undo this'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('cancelling the warning leaves the account alone', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsNothing);
  });

  group('type-to-confirm', () {
    testWidgets('shows the username, not the full Matrix ID', (tester) async {
      await pump(tester, client: buildTestClient(userId: '@alice:example.org'));

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('alice'), findsWidgets);
      expect(find.textContaining('@alice:example.org'), findsNothing);
      expect(find.textContaining('example.org'), findsNothing);
    });

    testWidgets(
      'Delete account stays disabled until the username matches exactly',
      (tester) async {
        await pump(
          tester,
          client: buildTestClient(userId: '@alice:example.org'),
        );

        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        Finder deleteButton() =>
            find.widgetWithText(TextButton, 'Delete account');

        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'alic');
        await tester.pump();
        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), '@alice:example.org');
        await tester.pump();
        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'alice');
        await tester.pump();
        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNotNull);
      },
    );

    testWidgets('cancelling here leaves the account alone too', (tester) async {
      await pump(tester, client: buildTestClient(userId: '@alice:example.org'));

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });
  });
}
