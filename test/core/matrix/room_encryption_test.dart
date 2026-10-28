import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_encryption.dart';

import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';

void main() {
  late StoredEventsFakeDatabaseApi db;
  late Client client;
  late Room room;

  void openRoom({bool encrypting = true}) {
    db = StoredEventsFakeDatabaseApi();
    client = buildTestClient(userId: _me, database: db, encrypting: encrypting);
    room = buildTestRoom(client)..partial = false;
    encryptRoom(room);
  }

  setUp(openRoom);

  Event text(
    String id, {
    String sender = _bob,
    bool encrypted = false,
    Map<String, Object?>? content,
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: sender,
    originServerTs: DateTime(2026, 10, 28, 12),
    status: EventStatus.synced,
    encrypted: encrypted,
    content: content ?? {'msgtype': 'm.text', 'body': 'hi'},
  );

  Event localCopy({String sender = _me}) => text(r'$m', sender: sender)
    ..status = EventStatus.sending
    ..unsigned = {messageSendingStatusKey: EventStatus.sending.intValue};

  Event edit(String target, {bool encrypted = false}) => text(
    r'$e',
    encrypted: encrypted,
    content: {
      'msgtype': 'm.text',
      'body': '* fixed',
      'm.new_content': {'msgtype': 'm.text', 'body': 'fixed'},
      'm.relates_to': {'rel_type': 'm.replace', 'event_id': target},
    },
  );

  Future<bool> inClear(List<Event> messages, {List<Event>? events}) async {
    db.events = events ?? messages;
    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    return sentInClear(messages, timeline);
  }

  test('a plain message in an encrypted chat was sent in clear', () async {
    expect(await inClear([text(r'$m')]), isTrue);
  });

  test('a decrypted message was not', () async {
    expect(await inClear([text(r'$m', encrypted: true)]), isFalse);
  });

  test('nothing in an unencrypted chat is marked', () async {
    room = buildTestRoom(client, id: '!plain:example.org')..partial = false;

    expect(await inClear([text(r'$m')]), isFalse);
  });

  test('a message that cannot be decrypted is not marked', () async {
    openRoom(encrypting: false);

    expect(
      await inClear([lockedTestEvent(room, eventId: r'$m', senderId: _bob)]),
      isFalse,
    );
  });

  test('a deleted message is not marked', () async {
    final deleted = text(r'$m')
      ..setRedactionEvent(buildTestRedaction(room, r'$m', senderId: _bob));

    expect(await inClear([deleted]), isFalse);
  });

  test('a room update is not marked', () async {
    final rename = buildTestEvent(
      room,
      eventId: r'$name',
      senderId: _bob,
      type: EventTypes.RoomName,
      stateKey: '',
      content: {'name': 'Lunch'},
    );

    expect(await inClear([rename]), isFalse);
  });

  group('your local copy', () {
    test('is not marked from a device that encrypts', () async {
      expect(await inClear([localCopy()]), isFalse);
    });

    test('is marked from a device that cannot encrypt', () async {
      openRoom(encrypting: false);

      expect(await inClear([localCopy()]), isTrue);
    });

    test('is not marked when it outlives the synced copy', () async {
      final raced = localCopy()..status = EventStatus.synced;

      expect(await inClear([raced]), isFalse);
    });

    test('gives way to the server copy, judged by its decryption', () async {
      expect(
        await inClear([text(r'$m', sender: _me, encrypted: true)]),
        isFalse,
      );
      expect(await inClear([text(r'$m', sender: _me)]), isTrue);
    });
  });

  test('a server cannot hide the mark by calling '
      "someone else's message unsent", () async {
    expect(await inClear([localCopy(sender: _bob)]), isTrue);
  });

  group('an edited message is judged by the edit shown', () {
    test('a plain edit of an encrypted message is marked', () async {
      final original = text(r'$m', encrypted: true);

      expect(
        await inClear([original], events: [edit(r'$m'), original]),
        isTrue,
      );
    });

    test('an encrypted edit of a plain message is not', () async {
      final original = text(r'$m');

      expect(
        await inClear(
          [original],
          events: [edit(r'$m', encrypted: true), original],
        ),
        isFalse,
      );
    });
  });

  group('a gallery', () {
    test('is marked when any photo in it was sent in clear', () async {
      expect(
        await inClear([text(r'$g1', encrypted: true), text(r'$g2')]),
        isTrue,
      );
    });

    test('is not marked when every photo was encrypted', () async {
      expect(
        await inClear([
          text(r'$g1', encrypted: true),
          text(r'$g2', encrypted: true),
        ]),
        isFalse,
      );
    });
  });
}
