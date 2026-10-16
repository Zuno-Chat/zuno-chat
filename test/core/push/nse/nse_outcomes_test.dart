import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/messages/notified_events_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notify_me.dart';
import 'package:zuno/core/push/nse/nse_app_channel.dart';
import 'package:zuno/core/push/nse/nse_outcomes.dart';
import 'package:zuno/core/push/nse/opaque_thread_ids.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/nse');
  late Map<String, Object?> replies;
  late SharedPreferences prefs;
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
    client = buildTestClient(userId: '@mwong:zuno.im');
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
    final shownAt = DateTime.now().millisecondsSinceEpoch;
    replies['takeMarks'] = [
      {'kind': 'invite', 'room': room.id, 'ts': shownAt},
    ];

    await reader().read();

    expect(
      inviteAnnouncedAt(prefs, room.id),
      DateTime.fromMillisecondsSinceEpoch(shownAt),
    );
  });

  test(
    'a refused credential is noticed once, through the auth counter',
    () async {
      replies['readOutcomes'] = [
        {'kind': 'counter', 'key': 'nse.c.20261002.o.auth', 'count': 1},
        {'kind': 'generation', 'value': 'g1'},
      ];
      final first = await reader().read();
      final again = await reader().read();

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
      await reader().read();
      replies['readOutcomes'] = [
        {'kind': 'generation', 'value': 'g2'},
      ];

      expect((await reader().read()).generationChanged, isTrue);
    },
  );

  test('only the auth counts of days the extension still keeps are stored, '
      'and a rise on any of them is noticed', () async {
    replies['readOutcomes'] = [
      {'kind': 'counter', 'key': 'nse.c.20261001.o.auth', 'count': 2},
      {'kind': 'counter', 'key': 'nse.c.20261001.o.shown', 'count': 40},
      {'kind': 'counter', 'key': 'nse.c.20261002.o.auth', 'count': 1},
    ];
    await reader().read();
    replies['readOutcomes'] = [
      {'kind': 'counter', 'key': 'nse.c.20261002.o.auth', 'count': 1},
    ];
    final steady = await reader().read();
    final stored = prefs.getString(NseOutcomeReader.countersKey);
    replies['readOutcomes'] = [
      {'kind': 'counter', 'key': 'nse.c.20261002.o.auth', 'count': 2},
    ];
    final risen = await reader().read();

    expect(steady.authFailed, isFalse);
    expect(stored, '{"nse.c.20261002.o.auth":1}');
    expect(risen.authFailed, isTrue);
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

  test('meta carries the level, notify mode, tone, unread tokens, mentions and '
      'the rooms asked to join', () async {
    client.homeserver = Uri.parse('https://zuno.im');
    final fields = await nseMetaFields(
      client: client,
      preview: NotificationPreview.nameOnly,
      notifyMe: NotifyMe.mentionsOnly,
      messageTone: false,
      unreadRoomIds: [room.id],
      threadIds: OpaqueThreadIds(threadKey: (id) async => 'tok-$id'),
      displayName: 'Mia',
      askedToJoin: {'!b:zuno.im', '!a:zuno.im'},
    );

    expect(fields['base_url'], 'https://zuno.im');
    expect(fields['level'], 'name');
    expect(fields['notify'], 'mentions');
    expect(fields['tone'], isFalse);
    expect(fields['unread'], ['tok-${room.id}']);
    expect((fields['mention'] as Map)['mxid'], '@mwong:zuno.im');
    expect(fields['asked'], ['!a:zuno.im', '!b:zuno.im']);
  });
}
