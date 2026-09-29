import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/room_info/presentation/room_access_label.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  void put(
    Room target,
    String type,
    Map<String, Object?> content, {
    String key = '',
  }) => target.setState(
    StrippedStateEvent(
      type: type,
      senderId: '@admin:example.org',
      stateKey: key,
      content: content,
    ),
  );

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client, id: '!gear:example.org')
      ..membership = Membership.join;
    client.rooms.add(room);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: RoomAccessLabel.of(room))),
  );

  testWidgets('a room open to its community names the community', (
    tester,
  ) async {
    put(room, EventTypes.RoomJoinRules, {'join_rule': 'restricted'});
    final club = buildTestRoom(client, id: '!club:example.org')
      ..membership = Membership.join;
    put(club, EventTypes.RoomCreate, {'type': 'm.space'});
    put(club, EventTypes.RoomName, {'name': 'Climbing club'});
    put(club, EventTypes.SpaceChild, {
      'via': ['example.org'],
    }, key: room.id);
    client.rooms.add(club);

    await pump(tester);

    expect(find.text('Climbing club'), findsOneWidget);
    expect(find.byIcon(Icons.workspaces_outlined), findsOneWidget);
  });

  testWidgets('without a known community it just says Community', (
    tester,
  ) async {
    put(room, EventTypes.RoomJoinRules, {'join_rule': 'restricted'});

    await pump(tester);

    expect(find.text('Community'), findsOneWidget);
  });

  testWidgets('a room people ask to join says so', (tester) async {
    put(room, EventTypes.RoomJoinRules, {'join_rule': 'knock'});

    await pump(tester);

    expect(find.text('Ask to join'), findsOneWidget);
    expect(find.byIcon(Icons.front_hand_outlined), findsOneWidget);
  });

  testWidgets('public and private keep their globes', (tester) async {
    put(room, EventTypes.RoomJoinRules, {'join_rule': 'public'});
    await pump(tester);
    expect(find.byIcon(Icons.public), findsOneWidget);

    put(room, EventTypes.RoomJoinRules, {'join_rule': 'invite'});
    await pump(tester);
    expect(find.byIcon(Icons.public_off), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
  });
}
