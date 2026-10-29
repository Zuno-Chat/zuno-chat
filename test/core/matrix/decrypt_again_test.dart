import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/decrypt_again.dart';

import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  test('without encryption it gives nothing back, never a throw', () async {
    final room = buildTestRoom(buildTestClient());
    final locked = lockedTestEvent(room, eventId: r'$1', senderId: '@a:x');

    expect(await decryptAgain(room.client, locked), isNull);
  });

  group('with encryption available', () {
    late FakeRoomDecryption encryption;
    late Room room;
    late Event locked;

    setUp(() {
      encryption = FakeRoomDecryption();
      room = buildTestRoom(DecryptingTestClient(encryption));
      locked = lockedTestEvent(room, eventId: r'$1', senderId: '@a:x');
    });

    test('a message whose key has arrived comes back readable', () async {
      encryption.decrypted.add(
        buildTestEvent(
          room,
          eventId: r'$1',
          senderId: '@a:x',
          content: {'msgtype': 'm.text', 'body': 'now readable'},
        ),
      );

      final opened = await decryptAgain(room.client, locked);

      expect(opened?.body, 'now readable');
    });

    test('a message still missing its key gives nothing back', () async {
      expect(await decryptAgain(room.client, locked), isNull);
      expect(encryption.attempts, 1);
    });
  });
}
