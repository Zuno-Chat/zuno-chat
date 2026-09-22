import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/room_info/presentation/people_trust_tile.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  late User bob;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.membership = Membership.join;
    bob = User('@bob:example.org', membership: 'invite', room: room);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        userTrustProvider('@bob:example.org')
            .overrideWithValue(UserTrustState.unconfirmed),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PeopleTrustTile(room: room, participants: [bob]),
        ),
      ),
    ),
  );

  testWidgets('offers no confirmation while the invitation is unanswered', (
    tester,
  ) async {
    room.summary = RoomSummary.fromJson({
      'm.heroes': ['@bob:example.org'],
      'm.joined_member_count': 1,
      'm.invited_member_count': 1,
    });

    await pump(tester);

    expect(find.text('You can confirm them once they join'), findsOneWidget);
    expect(find.textContaining("Confirm it's really"), findsNothing);
  });

  testWidgets('offers confirmation once they have joined', (tester) async {
    room.summary = RoomSummary.fromJson({
      'm.heroes': ['@bob:example.org'],
      'm.joined_member_count': 2,
      'm.invited_member_count': 0,
    });

    await pump(tester);

    expect(find.text('Confirm it is really @bob'), findsOneWidget);
    expect(find.text('You can confirm them once they join'), findsNothing);
  });
}
