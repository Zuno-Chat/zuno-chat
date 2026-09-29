import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/invite_notification_provider.dart';
import 'package:zuno/core/notifications/join_request_notification_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

const _me = '@me:example.org';

void main() {
  late Client client;
  late RecordedNotifications notifications;

  Future<ProviderContainer> container({List<String> asked = const []}) async {
    SharedPreferences.setMockInitialValues({'communities.asked.$_me': asked});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    client = buildTestClient(userId: _me);
  });

  Room named(String id, String name, Membership membership) {
    final room = buildTestRoom(client, id: id)..membership = membership;
    room.setState(
      Event(
        eventId: '\$name-$id',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2026),
        content: {'name': name},
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  group('invitations', () {
    Event invite(Room room) => Event(
      eventId: '\$invite-${room.id}',
      type: EventTypes.RoomMember,
      stateKey: _me,
      senderId: '@admin:example.org',
      originServerTs: DateTime.now(),
      content: {'membership': 'invite'},
      room: room,
    );

    test('an approval of a request stays quiet, since Zuno joins it', () async {
      final coaches = named('!coaches:x', 'Coaches', Membership.invite);
      final c = await container(asked: [coaches.id]);
      c.read(roomInviteNotificationProvider);

      client.onNotification.add(invite(coaches));
      await pumpEventQueue();

      expect(notifications.shown, isEmpty);
    });

    test('any other invitation still notifies', () async {
      final trips = named('!trips:x', 'Trips', Membership.invite);
      final c = await container();
      c.read(roomInviteNotificationProvider);

      client.onNotification.add(invite(trips));
      await pumpEventQueue();

      expect(notifications.shown.single.body, 'Invited you to Trips');
    });
  });

  group('requests to join', () {
    late Room room;

    setUp(() {
      room = named('!beginners:x', 'Beginners', Membership.join);
      room.setState(
        Event(
          eventId: r'$levels',
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: '@admin:example.org',
          originServerTs: DateTime(2026),
          content: {
            'users': {_me: 50},
            'invite': 0,
            'kick': 50,
          },
          room: room,
        ),
      );
    });

    test('a new request is shown to someone who can answer it', () async {
      final c = await container();
      c.read(joinRequestNotificationProvider);

      client.onTimelineEvent.add(
        Event(
          eventId: r'$knock',
          type: EventTypes.RoomMember,
          stateKey: '@maya:x',
          senderId: '@maya:x',
          originServerTs: DateTime.now(),
          content: {'membership': 'knock', 'displayname': 'Maya'},
          room: room,
        ),
      );
      await pumpEventQueue();

      final shown = notifications.shown.single;
      expect(shown.title, contains('Beginners'));
      expect(shown.body, 'Maya asks to join');
    });

    test('an ordinary message is not a request', () async {
      final c = await container();
      c.read(joinRequestNotificationProvider);

      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$msg',
          senderId: '@maya:x',
          content: {'msgtype': 'm.text', 'body': 'hi'},
        ),
      );
      await pumpEventQueue();

      expect(notifications.shown, isEmpty);
    });
  });
}
