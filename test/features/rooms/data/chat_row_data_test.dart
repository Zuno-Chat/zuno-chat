import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/events/event_display.dart';
import 'package:zuno/core/matrix/rooms/room_mute.dart';
import 'package:zuno/features/rooms/data/chat_row_data.dart';

import '../../../helpers/date_labels.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  final now = DateTime(2026, 9, 20, 15, 30);

  setUp(() {
    client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: FakeHttpClient((_) async => http.Response('{}', 200)),
    );
    client.setUserId('@me:example.org');
    room = buildTestRoom(client, notificationCount: 3)..partial = false;
    client.rooms.add(room);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [room.id],
      },
    );
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$bob',
        senderId: '@bob:example.org',
        type: EventTypes.RoomMember,
        stateKey: '@bob:example.org',
        content: {'membership': 'join', 'displayname': 'Bob'},
      ),
    );
    room.summary.mJoinedMemberCount = 2;
    room.summary.mInvitedMemberCount = 0;
    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$msg',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'Sure, talk soon'},
      originServerTs: DateTime(2026, 9, 20, 9, 41),
    );
  });

  ChatRowData read({Map<String, int> corrections = const {}}) => chatRowDataFor(
    room,
    unreadCorrections: corrections,
    now: now,
    labels: testDateLabels(),
  );

  void mute(Room room) => client.accountData['m.push_rules'] = BasicEvent(
    type: 'm.push_rules',
    content: {
      'global': {
        'override': [
          {
            'rule_id': room.id,
            'default': false,
            'enabled': true,
            'actions': <Object?>[],
            'conditions': [
              {'kind': 'event_match', 'key': 'room_id', 'pattern': room.id},
            ],
          },
        ],
      },
    },
  );

  test('reads what the row shows', () {
    final data = read();

    expect(data.roomId, room.id);
    expect(data.title, 'Bob');
    expect(data.isDirect, isTrue);
    expect(data.toneSeed, '@bob:example.org');
    expect(data.preview?.text, 'Sure, talk soon');
    expect(data.preview?.kind, MessageKind.text);
    expect(data.timeLabel, '09:41');
    expect(data.unread, 3);
    expect(data.muted, isFalse);
    expect(data.dimmed, isFalse);
    expect(data.partnerLeft, isFalse);
  });

  test('the same room state reads as an equal record', () {
    expect(read(), read());
    expect(read().hashCode, read().hashCode);
  });

  test('a new last message makes the record unequal', () {
    final before = read();
    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$msg2',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'One more thing'},
      originServerTs: DateTime(2026, 9, 20, 9, 50),
    );

    expect(read(), isNot(before));
  });

  test('an unread correction makes the record unequal', () {
    final before = read();

    final after = read(corrections: {room.id: 2});

    expect(after.unread, 1);
    expect(after, isNot(before));
  });

  test('a partner who left dims the row', () {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$bob-leave',
        senderId: '@bob:example.org',
        type: EventTypes.RoomMember,
        stateKey: '@bob:example.org',
        content: {'membership': 'leave', 'displayname': 'Bob'},
      ),
    );
    room.summary.mJoinedMemberCount = 1;

    final data = read();

    expect(data.partnerLeft, isTrue);
    expect(data.dimmed, isTrue);
  });

  test('muting the room makes the record unequal and dims the row', () {
    final before = read();
    mute(room);

    final after = read();

    expect(after.muted, isTrue);
    expect(after.dimmed, isTrue);
    expect(after, isNot(before));
  });

  test('someone typing makes the record unequal; my own typing does not', () {
    final before = read();
    room.ephemerals['m.typing'] = BasicEvent(
      type: 'm.typing',
      content: {
        'user_ids': ['@me:example.org'],
      },
    );
    expect(read(), before);

    room.ephemerals['m.typing'] = BasicEvent(
      type: 'm.typing',
      content: {
        'user_ids': ['@bob:example.org'],
      },
    );
    final after = read();

    expect(after.typingText, isNotNull);
    expect(after, isNot(before));
  });

  test('an invitation still waiting shows its status and no time', () {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$bob-invite',
        senderId: '@me:example.org',
        type: EventTypes.RoomMember,
        stateKey: '@bob:example.org',
        content: {'membership': 'invite', 'displayname': 'Bob'},
      ),
    );
    room.summary.mJoinedMemberCount = 1;
    room.summary.mInvitedMemberCount = 1;

    final data = read();

    expect(data.awaitingAcceptance, isTrue);
    expect(data.pendingInviteSubtitle, isNotEmpty);
    expect(data.timeLabel, isEmpty);
    expect(data.dimmed, isTrue);
  });

  test('turning encryption on makes the record unequal', () {
    client = buildTestClient(userId: '@me:example.org', encrypting: true);
    room = buildTestRoom(client)..partial = false;
    final before = read();
    expect(before.notEncrypted, isTrue);

    encryptRoom(room);
    final after = read();

    expect(after.notEncrypted, isFalse);
    expect(after, isNot(before));
  });

  test('an encrypted room on a client that cannot encrypt is marked as not '
      'encrypted', () {
    encryptRoom(room);

    expect(client.encryptionEnabled, isFalse);
    expect(read().notEncrypted, isTrue);
  });

  test('a mute asked of the server shows at once', () async {
    client
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'token';

    unawaited(setRoomMuted(room, true));
    await Future<void>.delayed(Duration.zero);

    expect(read().muted, isTrue);
  });

  test('a room without a last event has no time and no preview', () {
    room.lastEvent = null;

    final data = read();

    expect(data.timeLabel, isEmpty);
    expect(data.preview?.text, isNull);
    expect(data.lastEventId, isNull);
  });
}
