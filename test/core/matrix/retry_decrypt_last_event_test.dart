import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/retry_decrypt_last_event.dart';

import '../../helpers/fake_matrix.dart';

class _FakeEncryption extends Fake implements Encryption {
  _FakeEncryption(this.decrypt);

  final Event Function(Event event) decrypt;
  final storedAfterDecrypt = <bool>[];

  @override
  Future<Event> decryptRoomEvent(
    Event event, {
    bool store = false,
    EventUpdateType updateType = EventUpdateType.timeline,
  }) async {
    storedAfterDecrypt.add(store);
    return decrypt(event);
  }
}

class _EncryptingClient extends Client {
  _EncryptingClient(this._encryption)
    : super('test', database: FakeDatabaseApi());

  final Encryption _encryption;

  @override
  Encryption? get encryption => _encryption;
}

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

  group('with encryption available', () {
    late Room encryptedRoom;
    late _FakeEncryption encryption;
    late Event locked;

    void setUpDecrypting(Event Function(Event event) decrypt) {
      encryption = _FakeEncryption(decrypt);
      encryptedRoom = buildTestRoom(_EncryptingClient(encryption));
      locked = buildTestEvent(
        encryptedRoom,
        eventId: r'$1',
        senderId: '@a:x',
        type: EventTypes.Encrypted,
      );
      encryptedRoom.lastEvent = locked;
    }

    test('a message whose key has arrived becomes the room preview', () async {
      setUpDecrypting(
        (event) => buildTestEvent(
          encryptedRoom,
          eventId: event.eventId,
          senderId: event.senderId,
          content: {'msgtype': 'm.text', 'body': 'now readable'},
        ),
      );

      final result = await retryDecryptIfUndecryptable(encryptedRoom, locked);

      expect(result?.body, 'now readable');
      expect(encryptedRoom.lastEvent, same(result));
      expect(encryption.storedAfterDecrypt, [true]);
    });

    test('a message still missing its key keeps the old preview', () async {
      setUpDecrypting((event) => event);

      final result = await retryDecryptIfUndecryptable(encryptedRoom, locked);

      expect(result, isNull);
      expect(encryptedRoom.lastEvent, same(locked));
    });
  });
}
