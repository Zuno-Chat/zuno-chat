import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/room_updates.dart';

import '../../helpers/fake_matrix.dart';

const me = '@me:x';
const alex = '@alex:x';
const sam = '@sam:x';
const lee = '@lee:x';
const mia = '@mia:x';
const ben = '@ben:x';

void main() {
  late Client client;
  late Room room;
  final noon = DateTime(2026, 10, 17, 12);
  var seq = 0;

  setUp(() {
    seq = 0;
    client = buildTestClient(userId: me);
    room = buildTestRoom(client);
    client.rooms.add(room);
    for (final (id, name) in [
      (me, 'Me'),
      (alex, 'Alex'),
      (sam, 'Sam'),
      (lee, 'Lee'),
      (mia, 'Mia'),
      (ben, 'Ben'),
    ]) {
      room.setState(
        User(id, membership: 'join', displayName: name, room: room),
      );
    }
  });

  void makeDirect() {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        sam: [room.id],
      },
    );
  }

  Event member(
    String target,
    String membership, {
    String? by,
    String? was,
    String? name,
    DateTime? at,
  }) => buildTestEvent(
    room,
    eventId: '\$m${seq++}',
    senderId: by ?? target,
    type: EventTypes.RoomMember,
    stateKey: target,
    originServerTs: at ?? noon,
    content: {'membership': membership, 'displayname': ?name},
    prevContent: was == null ? null : {'membership': was, 'displayname': ?name},
  );

  Event state(
    String type,
    Map<String, Object?> content, {
    String by = alex,
    Map<String, Object?>? prev,
    String stateKey = '',
    DateTime? at,
  }) => buildTestEvent(
    room,
    eventId: '\$s${seq++}',
    senderId: by,
    type: type,
    stateKey: stateKey,
    originServerTs: at ?? noon,
    content: content,
    prevContent: prev,
  );

  Event levels(
    Map<String, int> users, {
    required Map<String, int> was,
    String by = alex,
  }) => state(
    EventTypes.RoomPowerLevels,
    {'users': users},
    by: by,
    prev: {'users': was},
  );

  Event text(String id, {DateTime? at}) => buildTestEvent(
    room,
    eventId: id,
    senderId: sam,
    originServerTs: at ?? noon,
    content: {'msgtype': 'm.text', 'body': id},
  );

  List<String> describe(List<Event> burst) =>
      describeRoomUpdates(englishLocalizations, burst);

  group('which updates show', () {
    test('membership changes in a room', () {
      for (final event in [
        member(sam, 'join'),
        member(sam, 'join', was: 'invite'),
        member(sam, 'leave', was: 'join'),
        member(sam, 'leave', by: alex, was: 'join'),
        member(sam, 'ban', by: alex, was: 'join'),
        member(sam, 'invite', by: alex),
        member(sam, 'leave', was: 'invite'),
        member(sam, 'leave', by: alex, was: 'invite'),
        member(sam, 'leave', by: alex, was: 'ban'),
        member(sam, 'knock'),
      ]) {
        expect(isRoomUpdate(event), isTrue, reason: '${event.content}');
      }
    });

    test('a profile change is not a room update', () {
      final rename = buildTestEvent(
        room,
        eventId: r'$p',
        senderId: sam,
        type: EventTypes.RoomMember,
        stateKey: sam,
        content: {'membership': 'join', 'displayname': 'Samuel'},
        prevContent: {'membership': 'join', 'displayname': 'Sam'},
      );
      final photo = buildTestEvent(
        room,
        eventId: r'$q',
        senderId: sam,
        type: EventTypes.RoomMember,
        stateKey: sam,
        content: {'membership': 'join', 'avatar_url': 'mxc://x/new'},
        prevContent: {'membership': 'join', 'avatar_url': 'mxc://x/old'},
      );

      expect(isRoomUpdate(rename), isFalse);
      expect(isRoomUpdate(photo), isFalse);
    });

    test('room details and role changes show; technical state does not', () {
      expect(isRoomUpdate(state(EventTypes.RoomCreate, {})), isTrue);
      expect(
        isRoomUpdate(state(EventTypes.RoomName, {'name': 'Trip'})),
        isTrue,
      );
      expect(isRoomUpdate(state(EventTypes.RoomTopic, {'topic': 'T'})), isTrue);
      expect(
        isRoomUpdate(state(EventTypes.RoomAvatar, {'url': 'mxc://x/a'})),
        isTrue,
      );
      expect(isRoomUpdate(levels({sam: 100}, was: {})), isTrue);

      expect(
        isRoomUpdate(
          state(
            EventTypes.RoomPowerLevels,
            {
              'users': {sam: 100},
              'events_default': 50,
            },
            prev: {
              'users': {sam: 100},
            },
          ),
        ),
        isFalse,
        reason: 'a permission change with no role change is technical',
      );
      expect(
        isRoomUpdate(
          state(EventTypes.RoomPowerLevels, {
            'users': {sam: 100},
          }),
        ),
        isFalse,
        reason: 'without the previous levels no role change can be named',
      );
      expect(
        isRoomUpdate(
          state(EventTypes.HistoryVisibility, {'history_visibility': 'shared'}),
        ),
        isFalse,
      );
      expect(
        isRoomUpdate(state(EventTypes.Encryption, {'algorithm': 'x'})),
        isFalse,
      );
      expect(
        isRoomUpdate(
          state('m.call.member', {'memberships': <Object?>[]}, stateKey: alex),
        ),
        isFalse,
      );
      expect(
        isRoomUpdate(
          state(EventTypes.RoomName, {'name': 'X'}, stateKey: 'odd'),
        ),
        isFalse,
      );
      expect(isRoomUpdate(text(r'$t')), isFalse);
    });

    test('a deleted room update is hidden', () {
      final event = state(EventTypes.RoomName, {});
      event.unsigned = {
        'redacted_because': {
          'event_id': r'$r',
          'type': EventTypes.Redaction,
          'sender': alex,
          'origin_server_ts': 0,
          'content': <String, Object?>{},
        },
      };

      expect(event.redacted, isTrue);
      expect(isRoomUpdate(event), isFalse);
    });

    test('a one-to-one chat shows only people leaving or being removed', () {
      makeDirect();

      expect(isRoomUpdate(member(sam, 'leave', was: 'join')), isTrue);
      expect(isRoomUpdate(member(sam, 'leave', by: alex, was: 'join')), isTrue);
      expect(isRoomUpdate(member(sam, 'ban', by: alex, was: 'join')), isTrue);

      expect(isRoomUpdate(member(sam, 'join', was: 'invite')), isFalse);
      expect(isRoomUpdate(member(sam, 'invite', by: me)), isFalse);
      expect(isRoomUpdate(state(EventTypes.RoomCreate, {})), isFalse);
      expect(isRoomUpdate(state(EventTypes.RoomName, {'name': 'X'})), isFalse);
      expect(isRoomUpdate(levels({sam: 100}, was: {})), isFalse);
    });
  });

  group('wording', () {
    test('people added by one person merge into one line', () {
      expect(
        describe([
          member(sam, 'invite', by: alex),
          member(lee, 'invite', by: alex),
          member(mia, 'invite', by: alex),
        ]),
        ['Alex invited Sam, Lee and Mia'],
      );
    });

    test('past three names the rest become a count', () {
      expect(
        describe([
          for (final id in [sam, lee, mia, ben]) member(id, 'join'),
        ]),
        ['Sam, Lee and 2 others joined'],
      );
    });

    test('each kind of change gets its own line, in the order it happened', () {
      expect(
        describe([
          member(sam, 'invite', by: alex),
          state(EventTypes.RoomName, {'name': 'Lisbon trip'}),
          member(lee, 'invite', by: alex),
          state(EventTypes.RoomAvatar, {'url': 'mxc://x/a'}),
          member(sam, 'join', was: 'invite'),
          member(lee, 'join', was: 'invite'),
        ]),
        [
          'Alex invited Sam and Lee',
          'Alex changed the room name to "Lisbon trip"',
          'Alex changed the room photo',
          'Sam and Lee joined',
        ],
      );
    });

    test('different people doing the same thing get separate lines', () {
      expect(
        describe([
          member(mia, 'invite', by: alex),
          member(ben, 'invite', by: sam),
        ]),
        ['Alex invited Mia', 'Sam invited Ben'],
      );
    });

    test('joining and leaving in one burst reads as one change', () {
      expect(
        describe([
          member(sam, 'join'),
          member(lee, 'join'),
          member(sam, 'leave', was: 'join'),
        ]),
        ['Sam joined and left', 'Lee joined'],
      );
    });

    test('a person counts once per line', () {
      expect(
        describe([
          member(sam, 'join'),
          member(sam, 'leave', was: 'join'),
          member(sam, 'join', was: 'leave'),
        ]),
        ['Sam joined'],
      );
    });

    test('a topic change does not repeat the topic', () {
      expect(
        describe([
          state(EventTypes.RoomTopic, {'topic': 'Weekend hikes around Lisbon'}),
        ]),
        ['Alex changed the room topic'],
      );
      expect(
        describe([
          state(EventTypes.RoomTopic, {'topic': 'Weekend hikes'}, by: me),
        ]),
        ['You changed the room topic'],
      );
    });

    test('only the final name, topic and photo show', () {
      expect(
        describe([
          state(EventTypes.RoomName, {'name': 'First'}),
          state(EventTypes.RoomName, {'name': 'Second'}, by: sam),
          state(EventTypes.RoomTopic, {'topic': 'One'}),
          state(EventTypes.RoomTopic, {'topic': ''}),
          state(EventTypes.RoomAvatar, {'url': 'mxc://x/a'}),
          state(EventTypes.RoomAvatar, {}),
        ]),
        [
          'Sam changed the room name to "Second"',
          'Alex removed the room topic',
          'Alex removed the room photo',
        ],
      );
    });

    test('creating a room hides the creator joining it', () {
      expect(
        describe([
          state(EventTypes.RoomCreate, {}),
          member(alex, 'join'),
          state(EventTypes.RoomPowerLevels, {
            'users': {alex: 100},
          }),
          state(EventTypes.RoomName, {'name': 'Trip'}),
          member(sam, 'invite', by: alex),
        ]),
        [
          'Alex created the room',
          'Alex changed the room name to "Trip"',
          'Alex invited Sam',
        ],
      );
    });

    test('the reader is "you"', () {
      expect(
        describe([
          state(EventTypes.RoomCreate, {}),
          member(me, 'invite', by: alex),
          member(me, 'join', was: 'invite'),
          member(sam, 'invite', by: me),
          member(lee, 'join'),
          state(EventTypes.RoomName, {'name': 'Trip'}, by: me),
        ]),
        [
          'Alex created the room',
          'Alex invited you',
          'You joined',
          'You invited Sam',
          'Lee joined',
          'You changed the room name to "Trip"',
        ],
      );
    });

    test('a room you created starts with you creating it', () {
      expect(
        describe([
          state(EventTypes.RoomCreate, {}, by: me),
          member(me, 'join'),
        ]),
        ['You created the room'],
      );
    });

    test('a creator who leaves and comes back reads as joined', () {
      expect(
        describe([
          state(EventTypes.RoomCreate, {}),
          member(alex, 'join'),
          member(alex, 'leave', was: 'join'),
          member(alex, 'join', was: 'leave'),
        ]),
        ['Alex created the room', 'Alex joined'],
      );
    });

    test('removals, bans and withdrawn invitations name who did them', () {
      expect(
        describe([
          member(sam, 'leave', by: alex, was: 'join'),
          member(lee, 'ban', by: alex, was: 'join'),
          member(mia, 'leave', by: alex, was: 'ban'),
          member(ben, 'leave', by: alex, was: 'invite'),
          member(me, 'leave', by: alex, was: 'join'),
        ]),
        [
          'Alex removed Sam',
          'Alex banned Lee',
          'Alex unbanned Mia',
          'Alex withdrew the invitation for Ben',
          'Alex removed you',
        ],
      );
    });

    test('declined invitations and requests to join', () {
      expect(
        describe([
          member(sam, 'leave', was: 'invite'),
          member(lee, 'knock'),
          member(mia, 'knock'),
        ]),
        ['Sam declined the invitation', 'Lee and Mia asked to join'],
      );
    });

    test('role changes name the new role', () {
      expect(
        describe([
          levels({sam: 100}, was: {}),
          levels({sam: 100, lee: 50, mia: 50}, was: {sam: 100}),
          levels(
            {sam: 100, lee: 50, mia: 50, me: 100},
            was: {sam: 100, lee: 50, mia: 50},
          ),
          levels(
            {lee: 50, mia: 50, me: 100},
            was: {sam: 100, lee: 50, mia: 50, me: 100},
            by: me,
          ),
        ]),
        [
          'You made Sam a member',
          'Alex made Lee and Mia moderators',
          'You are now an admin',
        ],
      );
    });

    test('a role changed twice shows only where it ended', () {
      expect(
        describe([
          levels({sam: 50}, was: {}),
          levels({sam: 100}, was: {sam: 50}),
        ]),
        ['Alex made Sam an admin'],
      );
    });

    test('read-only', () {
      expect(
        describe([
          levels({sam: -1}, was: {}),
        ]),
        ['Alex made Sam read-only'],
      );
    });
  });

  group('grouping a timeline', () {
    test('updates in a row become one burst anchored at the oldest', () {
      final newest = text(r'$t2');
      final second = member(lee, 'join');
      final first = member(sam, 'join');
      final oldest = text(r'$t1');

      final grouping = groupRoomUpdates([newest, second, first, oldest]);

      expect(grouping.messages, [newest, first, oldest]);
      expect(grouping.bursts, {
        first.eventId: [first, second],
      });
    });

    test('a message or a new day splits a burst', () {
      final yesterday = noon.subtract(const Duration(days: 1));
      final c = member(mia, 'join');
      final message = text(r'$t');
      final b = member(lee, 'join');
      final a = member(sam, 'join', at: yesterday);

      final grouping = groupRoomUpdates([c, message, b, a]);

      expect(grouping.messages, [c, message, b, a]);
      expect(grouping.bursts.keys, [c.eventId, b.eventId, a.eventId]);
    });

    test('a timeline without updates is unchanged', () {
      final events = [text(r'$b'), text(r'$a')];

      final grouping = groupRoomUpdates(events);

      expect(grouping.messages, events);
      expect(grouping.bursts, isEmpty);
    });
  });
}
