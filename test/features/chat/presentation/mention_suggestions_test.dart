import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/mention_suggestions.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Room room;
  late TextEditingController controller;
  var loads = 0;
  var fetched = <User>[];

  void join(String id, [String? name]) => room.setState(
    User(id, membership: 'join', displayName: name, room: room),
  );

  void completeSummary() {
    final members = room.getParticipants();
    room.summary.mJoinedMemberCount = members
        .where((u) => u.membership == Membership.join)
        .length;
    room.summary.mInvitedMemberCount = members
        .where((u) => u.membership == Membership.invite)
        .length;
  }

  setUp(() {
    final client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client)..partial = false;
    controller = TextEditingController();
    addTearDown(controller.dispose);
    loads = 0;
    fetched = [];
    join('@me:example.org', 'Me');
    join('@alice:example.org', 'Alice');
    join('@bob:example.org', 'Bob');
    room.setState(
      User(
        '@new:example.org',
        membership: 'invite',
        displayName: 'New',
        room: room,
      ),
    );
    completeSummary();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            MentionSuggestions(
              room: room,
              controller: controller,
              loadMembers: () async {
                loads++;
                return fetched;
              },
            ),
            TextField(controller: controller),
          ],
        ),
      ),
    ),
  );

  void type(String text) => controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  testWidgets('stays hidden until two characters follow the @', (tester) async {
    await pump(tester);
    type('@');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);

    type('@a');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);

    type('@al');
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Me'), findsNothing);
    expect(loads, 0);
  });

  testWidgets('narrows as you type and inserts the mention on tap', (
    tester,
  ) async {
    await pump(tester);
    type('hey @bo');
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(controller.text, 'hey @Bob ');
    expect(controller.selection.baseOffset, 9);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets(
    'fetches everyone once when the room is incomplete and a name is typed',
    (tester) async {
      room.summary.mJoinedMemberCount = 10;
      fetched = [
        User(
          '@zed:example.org',
          membership: 'join',
          displayName: 'Zed',
          room: room,
        ),
      ];
      await pump(tester);

      type('@');
      await tester.pumpAndSettle();
      expect(loads, 0);

      type('@ze');
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Zed'), findsOneWidget);

      type('@zed');
      await tester.pumpAndSettle();
      expect(loads, 1);
    },
  );

  testWidgets('never fetches when everyone is already known', (tester) async {
    await pump(tester);
    type('@zed');
    await tester.pumpAndSettle();

    expect(loads, 0);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('shows at most 30 rows', (tester) async {
    for (var i = 0; i < 40; i++) {
      join('@u$i:example.org', 'User $i');
    }
    completeSummary();
    await pump(tester);
    type('@us');
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 30);
  });

  testWidgets('shows nothing for a plain @ in an email or before a space', (
    tester,
  ) async {
    await pump(tester);
    type('write to foo@bar');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);

    type('@ ');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });
}
