import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/blocking/presentation/blocked_people_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late List<String> unblocked;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    unblocked = [];
  });

  void setBlocked(List<String> userIds) =>
      client.accountData['m.ignored_user_list'] = BasicEvent(
        type: 'm.ignored_user_list',
        content: {
          'ignored_users': {for (final id in userIds) id: <String, Object?>{}},
        },
      );

  Future<void> pumpPage(WidgetTester tester, {UnblockPerson? unblock}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          home: BlockedPeoplePage(
            unblock: unblock ?? (userId) async => unblocked.add(userId),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('blocked people sit on a card', (tester) async {
    setBlocked(['@ann:example.org']);
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('says so when nobody is blocked', (tester) async {
    await pumpPage(tester);

    expect(find.text('Nobody is blocked'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Unblock'), findsNothing);
  });

  testWidgets('lists blocked people by username, without the server', (
    tester,
  ) async {
    setBlocked(['@ann:example.org', '@ben:example.org']);
    await pumpPage(tester);

    expect(find.text('@ann'), findsOneWidget);
    expect(find.text('@ben'), findsOneWidget);
    expect(find.text('Nobody is blocked'), findsNothing);
  });

  testWidgets('Unblock unblocks that person and drops the row', (tester) async {
    setBlocked(['@ann:example.org', '@ben:example.org']);
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Unblock').first);
    await tester.pumpAndSettle();

    expect(unblocked, ['@ann:example.org']);
    expect(find.text('@ann'), findsNothing);
    expect(find.text('@ben'), findsOneWidget);
    expect(find.text('@ann unblocked'), findsOneWidget);
  });

  testWidgets('picks up someone blocked from another device', (tester) async {
    setBlocked(['@ann:example.org']);
    await pumpPage(tester);
    expect(find.text('@ben'), findsNothing);

    setBlocked(['@ann:example.org', '@ben:example.org']);
    client.onSync.add(
      SyncUpdate(
        nextBatch: 's1',
        accountData: [
          BasicEvent(type: 'm.ignored_user_list', content: const {}),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@ben'), findsOneWidget);
  });

  testWidgets('someone blocked again after an unblock shows again', (
    tester,
  ) async {
    setBlocked(['@ann:example.org']);
    await pumpPage(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(find.text('@ann'), findsNothing);

    client.onSync.add(
      SyncUpdate(
        nextBatch: 's2',
        accountData: [
          BasicEvent(type: 'm.ignored_user_list', content: const {}),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@ann'), findsOneWidget);
  });

  testWidgets('a refused unblock keeps the row and says to try again', (
    tester,
  ) async {
    setBlocked(['@ann:example.org']);
    await pumpPage(tester, unblock: (_) async => throw Exception('offline'));

    await tester.tap(find.widgetWithText(TextButton, 'Unblock'));
    await tester.pumpAndSettle();

    expect(find.text('@ann'), findsOneWidget);
    expect(find.text('Not unblocked. Try again.'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing);
  });
}
