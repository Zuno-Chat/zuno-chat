import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/official_room.dart';

import '../../helpers/fake_matrix.dart';

Room _room({String? creator, bool tagged = true}) {
  final client = buildTestClient(userId: '@alice:zuno.chat');
  final room = Room(
    id: '!room:zuno.chat',
    client: client,
    roomAccountData: tagged
        ? {
            'm.tag': BasicEvent(
              type: 'm.tag',
              content: {
                'tags': {'m.server_notice': <String, Object?>{}},
              },
            ),
          }
        : {},
  );
  if (creator != null) {
    room.setState(
      Event(
        eventId: '\$create',
        type: EventTypes.RoomCreate,
        senderId: creator,
        originServerTs: DateTime.now(),
        content: {'creator': creator},
        room: room,
        stateKey: '',
      ),
    );
  }
  return room;
}

void main() {
  test('the server notice room from the notices account is official', () {
    expect(isOfficialZunoRoom(_room(creator: officialNoticesUserId)), isTrue);
  });

  test('a room someone else created and tagged themselves is not', () {
    expect(isOfficialZunoRoom(_room(creator: '@mallory:zuno.chat')), isFalse);
  });

  test('an untagged room from the notices account is not', () {
    expect(
      isOfficialZunoRoom(_room(creator: officialNoticesUserId, tagged: false)),
      isFalse,
    );
  });

  test('an ordinary chat is not', () {
    expect(isOfficialZunoRoom(_room(tagged: false)), isFalse);
  });

  testWidgets('the badge names Zuno as the sender', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfficialBadge())),
    );

    expect(find.text('Official'), findsOneWidget);
  });
}
