import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/stored_inbound_group_session.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_preview.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/nse_credential.dart';
import 'package:zuno/core/push/read_model/nse_app_channel.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';
import 'package:zuno/core/push/read_model/nse_services.dart';
import 'package:zuno/core/push/read_model/opaque_thread_ids.dart';
import 'package:zuno/core/push/read_model/read_model_publisher.dart';
import 'package:zuno/core/push/read_model/session_exporter.dart';
import 'package:zuno/core/push/zuno_push_api.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

class _Sessions extends FakeDatabaseApi {
  final sessions = <String, StoredInboundGroupSession>{};

  void put(String roomId, String sessionId) =>
      sessions[sessionId] = StoredInboundGroupSession(
        roomId: roomId,
        sessionId: sessionId,
        pickle: 'pickle-$sessionId',
        content: '{}',
        indexes: '{}',
        allowedAtIndex: '{}',
        senderKey: 'curve-a',
        senderClaimedKeys: '{}',
      );

  @override
  Future<StoredInboundGroupSession?> getInboundGroupSession(
    String roomId,
    String sessionId,
  ) async => sessions[sessionId];

  @override
  Future<List<StoredInboundGroupSession>> getAllInboundGroupSessions() async =>
      sessions.values.toList();
}

class _Trimmer implements MegolmTrimmer {
  @override
  TrimmedSession? trim({
    required String pickle,
    required String userId,
    required int fromIndex,
  }) => TrimmedSession(pickle: 'trimmed-$pickle', firstIndex: fromIndex);
}

const _meta = (
  user: '@mwong:zuno.im',
  device: 'PHONE',
  serverOffsetMs: 0,
  ringtone: true,
  voipCurrent: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<Object?> outcomes;
  late SharedPreferences prefs;
  late Client client;
  late Room room;
  late ReadModelPublisher publisher;
  late NseSettings settings;
  late int mints;
  late List<String> unread;
  late List<String> asked;
  late OpaqueThreadIds threadIds;

  Map<String, Object?> lastJson(String method) => jsonDecode(
    (calls.lastWhere((c) => c.method == method).arguments as Map)['json']
        as String,
  ) as Map<String, Object?>;

  List<Object?> credentials() => [
    for (final call in calls)
      if (call.method == 'setCredential') (call.arguments as Map)['credential'],
  ];

  setUp(() async {
    ambientCapabilities = capabilitiesLike(
      iosCapabilities,
      voipRing: true,
      nseNotifications: true,
    );
    calls = [];
    outcomes = [];
    mints = 0;
    unread = [];
    asked = [];
    threadIds = OpaqueThreadIds(
      threadKey: (roomId) async {
        asked.add(roomId);
        return 'tok-$roomId';
      },
    );
    settings = (
      preview: NotificationPreview.full,
      notifyMe: NotifyMe.all,
      messageTone: true,
      allowed: true,
    );
    messenger.setMockMethodCallHandler(nseChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'threadKey' => 'tok-${(call.arguments as Map)['room_id']}',
        'setCredential' => true,
        'takeMarks' => <Object?>[],
        'readOutcomes' => outcomes,
        'syncBadge' => 0,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nseChannel, null));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final database = _Sessions()..put('!r:zuno.im', 's1');
    client = buildTestClient(
      userId: '@mwong:zuno.im',
      deviceId: 'PHONE',
      database: database,
    )..homeserver = Uri.parse('https://zuno.im');
    room = Room(id: '!r:zuno.im', client: client, membership: Membership.join)
      ..setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: '@mwong:zuno.im',
          stateKey: '',
          content: {'name': 'Design team'},
        ),
      );
    client.rooms.add(room);
    publisher = ReadModelPublisher();
    await publisher.start(client, _meta);
    calls.clear();
  });

  NseServices services() => NseServices(
    client: client,
    publisher: publisher,
    channel: NseAppChannel(capabilities: ambientCapabilities),
    prefs: prefs,
    settings: () => settings,
    unreadRoomIds: () => unread,
    mint: () async {
      mints++;
      return const ZunoPushOk(
        NseCredentialGrant(credential: 'cred', expiresTs: 1792592000000),
        serverTs: 1,
      );
    },
    exporter: SessionExporter(trimmer: _Trimmer()),
    threadIds: threadIds,
    appVersion: () async => '2.1+40',
    displayName: () async => 'Mia',
  );

  test('turns the extension on with meta, room files, a credential and the '
      'badge', () async {
    unread = [room.id];

    await services().start();

    final meta = lastJson('writeMeta');
    final file = lastJson('writeRoom');
    expect(meta['base_url'], 'https://zuno.im');
    expect(meta['level'], 'full');
    expect(meta['unread'], ['tok-!r:zuno.im']);
    expect((meta['mention'] as Map)['display_name'], 'Mia');
    expect(file['title'], 'Design team');
    expect((file['sessions'] as List).single, containsPair('session_id', 's1'));
    expect(credentials(), ['cred']);
    expect(calls.where((c) => c.method == 'syncBadge'), isNotEmpty);
  });

  test('Nothing takes titles, sessions and the credential away', () async {
    final nse = services();
    await nse.start();

    settings = (
      preview: NotificationPreview.nothing,
      notifyMe: NotifyMe.all,
      messageTone: true,
      allowed: true,
    );
    await nse.settingsChanged();

    final file = lastJson('writeRoom');
    expect(lastJson('writeMeta')['level'], 'none');
    expect(file['title'], '');
    expect(file['sessions'], isEmpty);
    expect(credentials(), ['cred', null]);
  });

  test(
    'without permission sessions and the credential go, titles stay',
    () async {
      final nse = services();
      await nse.start();

      settings = (
        preview: NotificationPreview.full,
        notifyMe: NotifyMe.all,
        messageTone: true,
        allowed: false,
      );
      await nse.settingsChanged();

      final file = lastJson('writeRoom');
      expect(file['title'], 'Design team');
      expect(file['sessions'], isEmpty);
      expect(credentials().last, isNull);
    },
  );

  test('a push-rule change rewrites the room files, so a muted room loses its '
      'sessions', () async {
    final nse = services();
    await nse.start();
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            {
              'rule_id': room.id,
              'default': false,
              'enabled': true,
              'conditions': <Object?>[],
              'actions': <Object?>[],
            },
          ],
        },
      },
    );
    calls.clear();

    await nse.synced(
      SyncUpdate(
        nextBatch: 'a',
        accountData: [BasicEvent(type: 'm.push_rules', content: {})],
      ),
    );

    expect(calls.where((c) => c.method == 'writeRoom'), isNotEmpty);
    expect(lastJson('writeRoom')['sessions'], isEmpty);
  });

  test('another account forgets the old credential and rebuilds', () async {
    await prefs.setString(NseServices.sessionKey, '@old:zuno.im|OLD');
    await prefs.setString(NseServices.buildKey, '1|2.1+40');
    await prefs.setInt(
      NseCredentialKeeper.mintedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    unread = [room.id];
    await threadIds.tokenFor(room.id);

    await services().start();

    expect(mints, 1);
    expect(prefs.getString(NseServices.sessionKey), '@mwong:zuno.im|PHONE');
    expect(asked.where((roomId) => roomId == room.id), hasLength(2));
  });

  test(
    'new extension keys mint at once and ask for every token again',
    () async {
      unread = [room.id];
      final nse = services();
      await nse.start();
      outcomes = [
        {'kind': 'generation', 'value': 'g1'},
      ];
      await nse.resumed();
      final askedBefore = asked.length;
      outcomes = [
        {'kind': 'generation', 'value': 'g2'},
      ];
      calls.clear();

      await nse.resumed();

      expect(mints, 2);
      expect(asked.length, greaterThan(askedBefore));
      expect(calls.where((c) => c.method == 'writeRoom'), isNotEmpty);
    },
  );

  test('a refused credential is minted again an hour later', () async {
    final nse = services();
    await nse.start();
    await prefs.setInt(
      NseCredentialKeeper.mintedKey,
      DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    );
    outcomes = [
      {'kind': 'counter', 'key': 'nse.c.20261002.o.auth', 'count': 1},
    ];

    await nse.resumed();

    expect(mints, 2);
  });

  test('the same unread rooms after a sync write nothing again', () async {
    final nse = services();
    await nse.start();
    unread = [room.id];
    calls.clear();

    await nse.synced(SyncUpdate(nextBatch: 'a'));
    await nse.synced(SyncUpdate(nextBatch: 'b'));

    expect(calls.where((c) => c.method == 'writeMeta'), hasLength(1));
    expect(calls.where((c) => c.method == 'syncBadge'), hasLength(1));
  });
}
