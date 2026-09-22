import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/undecryptable_event.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient());
  });

  test('a still-encrypted event (decryption never produced real content) is undecryptable', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      type: EventTypes.Encrypted,
    );
    expect(isUndecryptableEvent(event), isTrue);
  });

  test(
    'a successfully-decrypted message (rewritten to m.room.message) is not',
    () {
      final event = buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': 'hi'},
      );
      expect(isUndecryptableEvent(event), isFalse);
    },
  );
}
