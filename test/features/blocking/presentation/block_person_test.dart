import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/blocking/presentation/block_person.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late List<String> blocked;
  late List<bool> results;
  late Client client;

  setUp(() {
    blocked = [];
    results = [];
    client = buildTestClient(userId: '@me:example.org');
  });

  Future<void> openDialog(WidgetTester tester, {BlockPerson? block}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await confirmAndBlockPerson(
                  context,
                  client: client,
                  userId: '@ann:example.org',
                  name: 'Ann',
                  block: block ?? (userId) async => blocked.add(userId),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('says what blocking does before doing it', (tester) async {
    await openDialog(tester);

    expect(find.text('Block Ann?'), findsOneWidget);
    expect(
      find.textContaining(
        'Messages and invitations from Ann will no longer reach you',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('They are not told'), findsOneWidget);
    expect(blocked, isEmpty);
  });

  testWidgets('with no chat to lose, says nothing about one', (tester) async {
    await openDialog(tester);

    expect(find.textContaining('You leave your chat'), findsNothing);
  });

  testWidgets('says the chat is left for good when there is one', (
    tester,
  ) async {
    client.rooms.add(
      buildTestRoom(client, id: '!chat:example.org')
        ..membership = Membership.join,
    );
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@ann:example.org': ['!chat:example.org'],
      },
    );
    await openDialog(tester);

    expect(
      find.textContaining(
        'You leave your chat with Ann, and unblocking does not bring it back',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Cancel blocks nobody', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(blocked, isEmpty);
    expect(results, [false]);
    expect(find.text('Block Ann?'), findsNothing);
  });

  testWidgets('Block blocks the person and says so', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();

    expect(blocked, ['@ann:example.org']);
    expect(results, [true]);
    expect(find.text('Block Ann?'), findsNothing);
    expect(find.text('Ann blocked'), findsOneWidget);
  });

  testWidgets('holds both buttons while the block is on its way', (
    tester,
  ) async {
    final gate = Completer<void>();
    await openDialog(tester, block: (_) => gate.future);

    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Blocking…'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('a refused block stays open and says to try again', (
    tester,
  ) async {
    await openDialog(tester, block: (_) async => throw Exception('offline'));

    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();

    expect(find.text('Block Ann?'), findsOneWidget);
    expect(find.text('Not blocked. Try again.'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing);
    expect(results, isEmpty);
  });
}
