import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/retry_decrypt_last_event.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient());
  });

  test(
    'a plain (already-decrypted) message is left alone, no retry attempted',
    () async {
      final event = buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': 'hi'},
      );
      room.lastEvent = event;

      final result = await retryDecryptIfUndecryptable(room, event);

      expect(result, isNull);
      expect(room.lastEvent, same(event));
    },
  );

  test('an undecryptable event with no encryption available returns null, not a throw', () async {
    expect(room.client.encryption, isNull);
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      type: EventTypes.Encrypted,
    );
    room.lastEvent = event;

    final result = await retryDecryptIfUndecryptable(room, event);

    expect(result, isNull);
    expect(room.lastEvent, same(event));
  });
}
