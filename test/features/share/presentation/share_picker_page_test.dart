import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/optimistic_room_state.dart';
import 'package:zuno/features/share/presentation/share_picker_page.dart';

import '../../../helpers/fake_matrix.dart';

Room _named(
  Client client,
  String id,
  String name, {
  Membership membership = Membership.join,
}) {
  final room = Room(id: id, client: client, membership: membership);
  applyOptimisticRoomState(room, EventTypes.RoomName, {'name': name});
  return room;
}

void main() {
  late Client client;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
  });

  group('filterShareTargets', () {
    test('keeps joined rooms in the given order and drops the rest', () {
      final rooms = [
        _named(client, '!b:example.org', 'Bob'),
        _named(
          client,
          '!i:example.org',
          'Invite',
          membership: Membership.invite,
        ),
        _named(client, '!a:example.org', 'Alice'),
        _named(client, '!l:example.org', 'Left', membership: Membership.leave),
      ];
      expect(filterShareTargets(rooms, '').map((r) => r.id), [
        '!b:example.org',
        '!a:example.org',
      ]);
    });

    test('matches the display name case-insensitively', () {
      final rooms = [
        _named(client, '!a:example.org', 'Alice'),
        _named(client, '!b:example.org', 'Bob'),
      ];
      expect(filterShareTargets(rooms, ' aLi ').single.id, '!a:example.org');
      expect(filterShareTargets(rooms, 'zzz'), isEmpty);
    });
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharePickerPage(
          client: client,
          destination: (room) => Scaffold(body: Text('picked ${room.id}')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tapping a chat replaces the picker with the destination', (
    tester,
  ) async {
    client.rooms = [
      _named(client, '!a:example.org', 'Alice'),
      _named(client, '!b:example.org', 'Bob'),
    ];
    await pumpPicker(tester);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text('picked !b:example.org'), findsOneWidget);
    expect(find.byType(SharePickerPage), findsNothing);
  });

  testWidgets('searching narrows the list', (tester) async {
    client.rooms = [
      _named(client, '!a:example.org', 'Alice'),
      _named(client, '!b:example.org', 'Bob'),
    ];
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'bo');
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('no matches shows a calm empty line', (tester) async {
    client.rooms = [_named(client, '!a:example.org', 'Alice')];
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pump();

    expect(find.text('No chats found'), findsOneWidget);
  });
}
