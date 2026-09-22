import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/mention_fragments.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
  });

  Event message(Map<String, Object?> content) => buildTestEvent(
    room,
    eventId: r'$m',
    senderId: '@bob:example.org',
    content: {'msgtype': 'm.text', 'body': 'hi', ...content},
  );

  test('lists the fragments of intentionally mentioned members', () {
    room.setState(
      User(
        '@alice:example.org',
        membership: 'join',
        displayName: 'Alice Smith',
        room: room,
      ),
    );
    final event = message({
      'm.mentions': {
        'user_ids': ['@alice:example.org', '@carol:example.org'],
      },
    });

    expect(mentionFragmentsOf(event), {'@alice', '@[alice smith]', '@carol'});
  });

  test('is empty without intentional mentions', () {
    expect(mentionFragmentsOf(message({})), isEmpty);
    expect(
      mentionFragmentsOf(
        message({
          'm.mentions': {'room': true},
        }),
      ),
      isEmpty,
    );
  });
}
