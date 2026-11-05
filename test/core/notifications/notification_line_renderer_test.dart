import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/notification_line_renderer.dart';

import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  late StoredMembersFakeDatabaseApi db;
  late Client client;
  late Room room;
  late ClientNotificationRenderer renderer;

  setUp(() {
    db = StoredMembersFakeDatabaseApi()..displayNames['@a:x'] = 'Alice';
    client = buildTestClient(userId: '@me:x', database: db);
    room = buildTestRoom(client);
    client.rooms.add(room);
    renderer = ClientNotificationRenderer(client);
  });

  StoredNotificationLine stored(
    String eventId, {
    NotificationLineKind kind = NotificationLineKind.message,
    bool placeholder = false,
  }) => StoredNotificationLine(
    eventId: eventId,
    senderId: '@a:x',
    kind: kind,
    timestamp: DateTime.utc(2031),
    placeholder: placeholder,
  );

  test('rebuilds a line from its event in the database, with the sender as '
      'stored', () async {
    db.events.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': MessageTypes.Text, 'body': 'see you at noon'},
      ),
    );

    final line = await renderer.line(room.id, stored(r'$1'));

    expect(line.text, 'see you at noon');
    expect(line.senderName, 'Alice');
    expect(line.stored.eventId, r'$1');
  });

  test('a notice line is rebuilt by its own wording', () async {
    db.events.add(
      buildTestEvent(
        room,
        eventId: r'$v',
        senderId: '@a:x',
        content: {
          'msgtype': EventTypes.KeyVerificationRequest,
          'to': '@me:x',
          'body': 'Alice is requesting to verify',
        },
      ),
    );

    final line = await renderer.line(
      room.id,
      stored(r'$v', kind: NotificationLineKind.notice),
    );

    expect(line.text, 'Wants to verify you');
  });

  test('a placeholder, an event no longer in the database and one that '
      'cannot be read all say "New message"', () async {
    db.events
      ..add(lockedTestEvent(room, eventId: r'$locked', senderId: '@a:x'))
      ..add(
        buildTestEvent(
          room,
          eventId: r'$p',
          senderId: '@a:x',
          content: {'msgtype': MessageTypes.Text, 'body': 'not shown yet'},
        ),
      );

    for (final line in [
      stored(r'$p', placeholder: true),
      stored(r'$gone'),
      stored(r'$locked'),
    ]) {
      expect(
        (await renderer.line(room.id, line)).text,
        'New message',
        reason: line.eventId,
      );
    }
  });

  void setRoomState(
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
    String senderId = '@admin:x',
  }) => room.setState(
    Event(
      eventId: '\$$type$stateKey',
      type: type,
      stateKey: stateKey,
      senderId: senderId,
      originServerTs: DateTime(2026),
      content: content,
      room: room,
    ),
  );

  test('a placeholder is credited to the room, as when it was first '
      'shown', () async {
    setRoomState(EventTypes.RoomName, {'name': 'Climbing club'});

    final line = await renderer.line(room.id, stored(r'$p', placeholder: true));

    expect(line.senderName, 'Climbing club');
    expect(line.text, 'New message');
  });

  test("an invitation with no event of its own is rebuilt from the room's "
      'invite', () async {
    setRoomState(EventTypes.RoomName, {'name': 'Weekend plans'});
    setRoomState(
      EventTypes.RoomMember,
      {'membership': 'invite'},
      stateKey: '@me:x',
      senderId: '@a:x',
    );
    room.membership = Membership.invite;

    final line = await renderer.line(
      room.id,
      StoredNotificationLine(
        eventId: null,
        senderId: '@a:x',
        kind: NotificationLineKind.notice,
        timestamp: DateTime.utc(2031),
      ),
    );

    expect(line.text, 'Invited you to Weekend plans');
    expect(line.senderName, 'Alice');
  });

  test('a join request keeps the shortened name it was shown with', () async {
    setRoomState(EventTypes.RoomPowerLevels, {
      'users': {'@me:x': 100},
    });
    db.events.add(
      buildTestEvent(
        room,
        eventId: r'$knock',
        senderId: '@ines:x',
        type: EventTypes.RoomMember,
        stateKey: '@ines:x',
        content: {'membership': 'knock', 'displayname': 'I' * 200},
      ),
    );

    final line = await renderer.line(
      room.id,
      StoredNotificationLine(
        eventId: r'$knock',
        senderId: '@ines:x',
        kind: NotificationLineKind.notice,
        timestamp: DateTime.utc(2031),
      ),
    );

    expect(line.senderName.length, lessThan(200));
    expect(line.text, endsWith('asks to join'));
    expect(line.text, startsWith(line.senderName));
  });

  test('a sender picture comes only from members already in memory', () {
    room.setState(
      User(
        '@a:x',
        displayName: 'Alice',
        avatarUrl: 'mxc://x/alice',
        room: room,
      ),
    );

    expect(renderer.avatarOf(room.id, '@a:x'), Uri.parse('mxc://x/alice'));
    expect(renderer.avatarOf(room.id, '@b:x'), isNull);
    expect(renderer.avatarOf('!gone:x', '@a:x'), isNull);
  });

  test('a room the client no longer knows gets the generic line and '
      'title', () async {
    final line = await renderer.line('!gone:x', stored(r'$1'));

    expect(line.text, 'New message');
    expect(line.senderName, 'New message');
    expect(await renderer.title('!gone:x'), 'New message');
  });

  test('a title waits for the members that name the chat', () async {
    room.summary.mHeroes = ['@a:x'];

    expect(await renderer.title(room.id), 'Group with Alice');
  });
}
