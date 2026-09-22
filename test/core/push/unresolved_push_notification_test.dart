import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  final client = buildTestClient();

  group('a push whose event could not be fetched', () {
    test('still says something, routed to the room it came from', () {
      expect(
        unresolvedPushNotification(
          client,
          const PushNotification(roomId: '!room:example.org', eventId: r'$e'),
        ),
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'New message',
          body: 'Tap to open',
          text: 'New message',
          eventId: r'$e',
          senderName: 'New message',
        ),
      );
    });

    test('names the room when the gateway sent a name', () {
      expect(
        unresolvedPushNotification(
          client,
          const PushNotification(
            roomId: '!room:example.org',
            roomName: 'Weeknight plans',
          ),
        )?.title,
        'Weeknight plans',
      );
    });

    test('falls back to the sender when there is no room name', () {
      expect(
        unresolvedPushNotification(
          client,
          const PushNotification(
            roomId: '!room:example.org',
            senderDisplayName: 'Ada',
          ),
        )?.title,
        'Ada',
      );
    });
  });

  group('what it refuses to show', () {
    test('nothing at all without a room to open', () {
      expect(
        unresolvedPushNotification(client, const PushNotification()),
        isNull,
      );
    });

    test('nothing for a clear-out push with no room', () {
      expect(
        unresolvedPushNotification(
          client,
          const PushNotification(counts: PushNotificationCounts(unread: 0)),
        ),
        isNull,
      );
    });
  });

  test('names the room from the local cache when the gateway sent no name', () {
    final local = buildTestClient();
    final room = buildTestRoom(local, id: '!known:example.org');
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$name',
        senderId: '@a:x',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Team'},
      ),
    );
    local.rooms.add(room);

    final content = unresolvedPushNotification(
      local,
      const PushNotification(roomId: '!known:example.org', eventId: r'$e'),
    );

    expect(content?.title, 'Team');
    expect(content?.text, 'New message');
  });
}
