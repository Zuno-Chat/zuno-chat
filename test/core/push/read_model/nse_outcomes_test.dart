import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/notification_preview.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/push/read_model/nse_app_channel.dart';
import 'package:zuno/core/push/read_model/nse_outcomes.dart';
import 'package:zuno/core/push/read_model/opaque_thread_ids.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/nse');
  late Map<String, Object?> replies;
  late SharedPreferences prefs;
  late StoredEventsFakeDatabaseApi database;
  late Client client;
  late Room room;

  setUp(() async {
    replies = {'takeMarks': <Object?>[], 'readOutcomes': <Object?>[]};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => replies[call.method],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    database = StoredEventsFakeDatabaseApi();
    client = buildTestClient(userId: '@mwong:zuno.im', database: database);
    room = buildTestRoom(client, id: '!r:zuno.im');
    client.rooms.add(room);
  });

  NseOutcomeReader reader() => NseOutcomeReader(
    channel: NseAppChannel(
      capabilities: capabilitiesLike(iosCapabilities, nseNotifications: true),
    ),
    prefs: prefs,
  );

  test('an invitation the extension showed is never announced again', () async {
    replies['takeMarks'] = [
      {
        'kind': 'invite',
        'room': room.id,
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
      {'kind': 'test', 'ts': 42},
    ];

    await reader().read(client);

    expect(inviteAnnouncedAt(prefs, room.id), isNotNull);
    expect(prefs.getInt(NseOutcomeReader.testAckKey), 42);
  });

  test(
    'a refused credential is noticed once, through the auth counter',
    () async {
      replies['readOutcomes'] = [
        {'kind': 'counter', 'key': 'nse.c.20261002.o.auth', 'count': 1},
        {'kind': 'generation', 'value': 'g1'},
      ];
      final first = await reader().read(client);
      final again = await reader().read(client);

      expect(first.authFailed, isTrue);
      expect(again.authFailed, isFalse);
      expect(first.generationChanged, isFalse);
      expect(again.generationChanged, isFalse);
    },
  );

  test(
    'new extension keys are noticed so everything is published again',
    () async {
      replies['readOutcomes'] = [
        {'kind': 'generation', 'value': 'g1'},
      ];
      await reader().read(client);
      replies['readOutcomes'] = [
        {'kind': 'generation', 'value': 'g2'},
      ];

      expect((await reader().read(client)).generationChanged, isTrue);
    },
  );

  test('a fallback that the app later read counts as a late key, one that '
      'stayed sealed as missing', () async {
    database.events = [
      buildTestEvent(
        room,
        eventId: r'$late',
        senderId: '@a:zuno.im',
        content: {'body': 'hi'},
      ),
      buildTestEvent(
        room,
        eventId: r'$sealed',
        senderId: '@a:zuno.im',
        type: EventTypes.Encrypted,
        content: {'ciphertext': 'x'},
      ),
    ];
    replies['readOutcomes'] = [
      {'kind': 'utd', 'room': room.id, 'event': r'$late', 'ts': 1},
      {'kind': 'utd', 'room': room.id, 'event': r'$sealed', 'ts': 2},
      {'kind': 'utd', 'room': '!gone:zuno.im', 'event': r'$x', 'ts': 3},
    ];

    await reader().read(client);

    expect(prefs.getInt(NseOutcomeReader.lateKeysKey), 1);
    expect(prefs.getInt(NseOutcomeReader.missingKeysKey), 1);
  });

  test('the badge counts unread rooms and invitations only', () {
    final quiet = buildTestRoom(client, id: '!quiet:zuno.im');
    final unread = buildTestRoom(
      client,
      id: '!unread:zuno.im',
      notificationCount: 2,
    );
    final corrected = buildTestRoom(
      client,
      id: '!calls:zuno.im',
      notificationCount: 1,
    );
    final invited = buildTestRoom(client, id: '!invite:zuno.im')
      ..membership = Membership.invite;
    client.rooms
      ..clear()
      ..addAll([quiet, unread, corrected, invited]);

    expect(badgeRoomIds(client, {corrected.id: 1}), [unread.id, invited.id]);
  });

  test(
    'meta carries the level, notify mode, tone, unread tokens and mentions',
    () async {
      client.homeserver = Uri.parse('https://zuno.im');
      final fields = await nseMetaFields(
        client: client,
        preview: NotificationPreview.nameOnly,
        notifyMe: NotifyMe.mentionsOnly,
        messageTone: false,
        unreadRoomIds: [room.id],
        threadIds: OpaqueThreadIds(threadKey: (id) async => 'tok-$id'),
        displayName: 'Mia',
      );

      expect(fields['base_url'], 'https://zuno.im');
      expect(fields['level'], 'name');
      expect(fields['notify'], 'mentions');
      expect(fields['tone'], isFalse);
      expect(fields['unread'], ['tok-${room.id}']);
      expect((fields['mention'] as Map)['mxid'], '@mwong:zuno.im');
    },
  );
}
