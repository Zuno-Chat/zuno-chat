import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
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
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: RoomAccessLabel.of(room, englishLocalizations)),
    ),
  );

  Room community(String id, String name) {
    final space = buildTestRoom(client, id: id)..membership = Membership.join;
    put(space, EventTypes.RoomCreate, {'type': 'm.space'});
    put(space, EventTypes.RoomName, {'name': name});
    put(space, EventTypes.SpaceChild, {
      'via': ['example.org'],
    }, key: room.id);
    put(room, EventTypes.SpaceParent, {
      'via': ['example.org'],
    }, key: id);
    client.rooms.add(space);
    return space;
  }

  void openTo(List<String> communities) => put(room, EventTypes.RoomJoinRules, {
    'join_rule': 'restricted',
    'allow': [
      for (final id in communities)
        {'type': 'm.room_membership', 'room_id': id},
    ],
  });

  testWidgets('a room open to its community names the community', (
    tester,
  ) async {
    final club = community('!club:example.org', 'Climbing club');
    openTo([club.id]);

    await pump(tester);

    expect(find.text('Climbing club'), findsOneWidget);
    expect(find.byIcon(Icons.workspaces_outlined), findsOneWidget);
  });

  testWidgets('names the community whose members can join, not another that '
      'holds the room', (tester) async {
    community('!hall:example.org', 'Town hall');
    final club = community('!club:example.org', 'Climbing club');
    openTo([club.id]);

    await pump(tester);

    expect(find.text('Climbing club'), findsOneWidget);
    expect(find.text('Town hall'), findsNothing);
  });

  testWidgets('a community you are not in is not named', (tester) async {
    openTo(['!elsewhere:example.org']);

    await pump(tester);

    expect(find.text('Community'), findsOneWidget);
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
