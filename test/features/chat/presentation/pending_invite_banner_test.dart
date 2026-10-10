import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/pending_invite_banner.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    client.rooms.add(room);
    room.setState(User('@me:example.org', membership: 'join', room: room));
  });

  void member(String id, String membership) =>
      room.setState(User(id, membership: membership, room: room));

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: PendingInviteBanner(room: room)),
    ),
  );

  testWidgets('names the one person who has not accepted yet', (tester) async {
    member('@bob:example.org', 'invite');
    await pump(tester);

    expect(find.text('Waiting for @bob to accept'), findsOneWidget);
    expect(
      find.text('Your messages will be here when they join.'),
      findsOneWidget,
    );
  });

  testWidgets('is not shown with nobody invited', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
  });
}
