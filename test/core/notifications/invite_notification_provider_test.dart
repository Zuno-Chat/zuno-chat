import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/notifications/invite_notification_provider.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.membership = Membership.invite;
    room.setState(
      User(
        '@alice:example.org',
        displayName: 'Alice',
        membership: 'join',
        room: room,
      ),
    );
  });

  Event inviteEvent({
    String stateKey = '@me:example.org',
    String membership = 'invite',
    String senderId = '@alice:example.org',
    String type = EventTypes.RoomMember,
  }) {
    return Event(
      eventId: r'$invite',
      type: type,
      stateKey: stateKey,
      senderId: senderId,
      originServerTs: DateTime.now(),
      content: {'membership': membership},
      room: room,
    );
  }

  test('notifies for an invitation addressed to this user', () {
    final content = inviteNotificationFor(client, inviteEvent());

    expect(content, isNotNull);
    expect(content!.roomId, room.id);
    expect(content.title, 'Alice');
    expect(content.body, 'Invited you to chat');
    expect(content.isDirectChat, isFalse);
  });

  test('names the group when the room has a name of its own', () {
    room.setState(
      Event(
        eventId: r'$name',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: '@alice:example.org',
        originServerTs: DateTime.now(),
        content: {'name': 'Weekend plans'},
        room: room,
      ),
    );

    expect(
      inviteNotificationFor(client, inviteEvent())?.body,
      'Invited you to Weekend plans',
    );
  });

  test('ignores an invitation addressed to someone else', () {
    expect(
      inviteNotificationFor(client, inviteEvent(stateKey: '@bob:example.org')),
      isNull,
    );
  });

  test('ignores a membership change that is not an invitation', () {
    expect(
      inviteNotificationFor(client, inviteEvent(membership: 'join')),
      isNull,
    );
  });

  test('ignores an ordinary message event', () {
    expect(
      inviteNotificationFor(client, inviteEvent(type: EventTypes.Message)),
      isNull,
    );
  });

  test('ignores an invitation this user somehow sent themselves', () {
    expect(
      inviteNotificationFor(client, inviteEvent(senderId: '@me:example.org')),
      isNull,
    );
  });

  test('carries the invite event id so a notice for it can be replaced', () {
    final content = inviteNotificationFor(client, inviteEvent());

    expect(content?.eventId, r'$invite');
  });
}
