import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/push/nse/session_exporter.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_megolm_sessions.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/platform_capabilities.dart';

class _Events implements InboundSessionEvents {
  final stored = <String>[];
  final updated = <(String, String?, String)>[];

  @override
  void sessionStored({
    required String roomId,
    required String sessionId,
    required String content,
  }) => stored.add('$roomId/$sessionId $content');

  @override
  void sessionIndexesUpdated({
    required String roomId,
    required String sessionId,
    required String? previous,
    required String indexes,
  }) => updated.add((sessionId, previous, indexes));
}

class _ThrowingEvents implements InboundSessionEvents {
  @override
  void sessionStored({
    required String roomId,
    required String sessionId,
    required String content,
  }) => throw StateError('listener');

  @override
  void sessionIndexesUpdated({
    required String roomId,
    required String sessionId,
    required String? previous,
    required String indexes,
  }) => throw StateError('listener');
}

class _HookedDatabase extends SessionStoreFakeDatabaseApi
    with InboundSessionHooks {
  _HookedDatabase(this.inboundSessionEvents);

  @override
  final InboundSessionEvents inboundSessionEvents;
}

final Object _needsMacLibrary = Platform.isMacOS
    ? false
    : 'needs the macOS vodozemac build';

String _macLibrary() {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final package = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((package) => package['name'] == 'flutter_vodozemac');
  final root = Directory('.dart_tool').absolute.uri
      .resolve('${package['rootUri']}/');
  return root
      .resolve(
        'macos/flutter_vodozemac/flutter_vodozemac.xcframework/macos-arm64_x86_64/',
      )
      .toFilePath();
}

String _indexes(Map<int, int> decrypted) => jsonEncode({
  for (final MapEntry(:key, :value) in decrypted.entries)
    'key-$key': '\$e$key|$value',
});

const _forwarded =
    '{"algorithm":"m.megolm.v1.aes-sha2","forwarding_curve25519_key_chain":[]}';

class _SyncedClient extends Client {
  _SyncedClient(DatabaseApi database) : super('test', database: database);

  @override
  String? get prevBatch => 's1';
}

void main() {
  test(
    'only the app client on a device with the extension exports sessions',
    () {
      final ios = capabilitiesLike(iosCapabilities, nseNotifications: true);

      expect(
        exportsInboundSessions(appClient: true, capabilities: ios),
        isTrue,
      );
      expect(
        exportsInboundSessions(appClient: false, capabilities: ios),
        isFalse,
      );
      expect(
        exportsInboundSessions(
          appClient: true,
          capabilities: androidCapabilities,
        ),
        isFalse,
      );
    },
  );

  group('the database hooks', () {
    Future<void> storeSession(_HookedDatabase database) =>
        database.storeInboundGroupSession(
          '!r',
          's1',
          'p',
          _forwarded,
          '{}',
          '{}',
          'k',
          '{}',
        );

    test(
      'report stored sessions and index updates with what came before',
      () async {
        final events = _Events();
        final database = _HookedDatabase(events);
        await storeSession(database);
        await database.updateInboundGroupSessionIndexes(
          _indexes({0: 1}),
          '!r',
          's1',
        );

        expect(events.stored, ['!r/s1 $_forwarded']);
        expect(events.updated.single, ('s1', '{}', _indexes({0: 1})));
      },
    );

    test('report nothing when the write fails', () async {
      final events = _Events();
      final database = _HookedDatabase(events)..failWrites = true;

      await expectLater(storeSession(database), throwsStateError);
      expect(events.stored, isEmpty);
    });

    test('keep the write whole when the listener throws', () async {
      final database = _HookedDatabase(_ThrowingEvents());

      await storeSession(database);
      await database.updateInboundGroupSessionIndexes(
        _indexes({0: 1}),
        '!r',
        's1',
      );

      expect(database.sessions['s1']?.indexes, _indexes({0: 1}));
    });
  });

  group('choosing sessions', () {
    test('keeps the newest per sender device and every unused one', () {
      final chosen = selectSessions([
        const SessionCandidate(
          sessionId: 'old',
          senderKey: 'a',
          recencyMs: 1,
          used: true,
        ),
        const SessionCandidate(
          sessionId: 'new',
          senderKey: 'a',
          recencyMs: 5,
          used: true,
        ),
        const SessionCandidate(
          sessionId: 'b',
          senderKey: 'b',
          recencyMs: 3,
          used: true,
        ),
        const SessionCandidate(
          sessionId: 'fresh',
          senderKey: 'a',
          recencyMs: 9,
          used: false,
        ),
      ]);

      expect(chosen, ['fresh', 'new', 'b']);
    });

    test('never exports more than eight', () {
      final chosen = selectSessions([
        for (var i = 0; i < 12; i++)
          SessionCandidate(
            sessionId: 's$i',
            senderKey: 'k$i',
            recencyMs: i,
            used: false,
          ),
      ]);

      expect(chosen, hasLength(8));
      expect(chosen.first, 's11');
    });
  });

  group('the trim point', () {
    final now = DateTime(2026, 10, 2, 12);

    test('follows the newest index read at least two minutes ago', () {
      expect(
        trimPoint(
          decrypted: {3: 0, 4: 0, 5: 0},
          firstSeen: {5: now.subtract(const Duration(seconds: 30))},
          now: now,
        ),
        5,
      );
    });

    test(
      'after a restart a recent event keeps its grace through its own time',
      () {
        expect(
          trimPoint(
            decrypted: {
              3: now
                  .subtract(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
              4: now
                  .subtract(const Duration(seconds: 30))
                  .millisecondsSinceEpoch,
            },
            firstSeen: const {},
            now: now,
          ),
          4,
        );
      },
    );

    test('starts at the lowest index read while every one is in its grace', () {
      expect(
        trimPoint(
          decrypted: {9: 0, 7: 0},
          firstSeen: {7: now, 9: now},
          now: now,
        ),
        7,
      );
    });

    test('is the first known index while nothing was read', () {
      expect(
        trimPoint(decrypted: const {}, firstSeen: const {}, now: now),
        isNull,
      );
    });

    test('never starts before where the session was last exported from', () {
      expect(
        trimPoint(
          decrypted: {3: 0},
          firstSeen: const {},
          now: now,
          exportedFrom: 9,
        ),
        9,
      );
      expect(
        trimPoint(
          decrypted: {2: 0},
          firstSeen: {2: now},
          now: now,
          exportedFrom: 9,
        ),
        9,
      );
      expect(
        trimPoint(
          decrypted: const {},
          firstSeen: const {},
          now: now,
          exportedFrom: 4,
        ),
        4,
      );
      expect(
        trimPoint(
          decrypted: {12: 0},
          firstSeen: const {},
          now: now,
          exportedFrom: 5,
        ),
        13,
      );
    });

    test('reads indexes the SDK stores and shrugs off garbage', () {
      expect(decryptedIndexes(_indexes({2: 100, 9: 200})), {2: 100, 9: 200});
      expect(decryptedIndexes('not json'), isEmpty);
      expect(decryptedIndexes('{"other": 1, "key-x": "y"}'), isEmpty);
      expect(decryptedIndexes(null), isEmpty);
    });
  });

  group('the exporter', () {
    var now = DateTime(2026, 10, 2, 12);
    late SessionStoreFakeDatabaseApi database;
    late Client client;
    late Room room;
    late FakeMegolmTrimmer trimmer;
    late SessionExporter exporter;

    setUp(() {
      now = DateTime(2026, 10, 2, 12);
      database = SessionStoreFakeDatabaseApi();
      client = buildTestClient(userId: '@mwong:zuno.im', database: database);
      room = buildTestRoom(client, id: '!r:zuno.im');
      trimmer = FakeMegolmTrimmer();
      exporter = SessionExporter(trimmer: trimmer, now: () => now);
    });

    test(
      'marks a room dirty for a new session and trims it from its start',
      () async {
        database.put(room.id, 's1');
        exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');

        expect(exporter.takeDirtyRooms(), {room.id});
        final fields = await exporter.roomFields(room, allowed: true);

        expect(fields['sessions'], [
          {
            'session_id': 's1',
            'sender_key': 'curve-a',
            'first_index': 0,
            'pickle': 'trimmed-pickle-s1',
          },
        ]);
        expect(trimmer.calls, ['pickle-s1@0']);
      },
    );

    test(
      'keeps a just-read index exportable for two minutes, then trims it',
      () async {
        database.put(room.id, 's1', indexes: _indexes({0: 1, 1: 2}));
        exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');
        exporter.sessionIndexesUpdated(
          roomId: room.id,
          sessionId: 's1',
          previous: _indexes({0: 1}),
          indexes: _indexes({0: 1, 1: 2}),
        );
        exporter.takeDirtyRooms();

        await exporter.roomFields(room, allowed: true);
        now = now.add(const Duration(minutes: 3));
        expect(exporter.takeDirtyRooms(), {room.id});
        await exporter.roomFields(room, allowed: true);

        expect(trimmer.calls, ['pickle-s1@1', 'pickle-s1@2']);
      },
    );

    test('trims a room once until one of its sessions changes', () async {
      database.put(room.id, 's1');
      exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');

      await exporter.roomFields(room, allowed: true);
      await exporter.roomFields(room, allowed: true);
      exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');
      await exporter.roomFields(room, allowed: true);

      expect(trimmer.calls, ['pickle-s1@0', 'pickle-s1@0']);
    });

    List<Object?> exported(Map<String, Object?> fields) => [
      for (final session in fields['sessions'] as List)
        (session as Map)['session_id'],
    ];

    test('a session stored while a room is trimmed neither breaks the pass '
        'nor hides behind its cached result', () async {
      database.put(room.id, 's1');
      database.put(room.id, 's2');
      exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');
      exporter.sessionStored(roomId: room.id, sessionId: 's2', content: '{}');
      database.duringRead = () {
        database.duringRead = null;
        database.put(room.id, 's3');
        exporter.sessionStored(roomId: room.id, sessionId: 's3', content: '{}');
      };

      final during = await exporter.roomFields(room, allowed: true);
      final after = await exporter.roomFields(room, allowed: true);

      expect(exported(during), containsAll(['s1', 's2']));
      expect(exported(after), containsAll(['s1', 's2', 's3']));
    });

    test('a read that fails exports nothing for the room and is tried again '
        'next time', () async {
      database.put(room.id, 's1');
      exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');
      database.failReads = true;

      final failed = await exporter.roomFields(room, allowed: true);
      database.failReads = false;
      final retried = await exporter.roomFields(room, allowed: true);

      expect(failed['sessions'], isEmpty);
      expect(failed.containsKey('notifiers'), isTrue);
      expect(exported(retried), ['s1']);
    });

    test('exports nothing when not allowed or idle, but still names '
        'notifiers', () async {
      database.put(room.id, 's1');
      exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');

      final denied = await exporter.roomFields(room, allowed: false);
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'body': 'old'},
        senderId: '@a:zuno.im',
        eventId: r'$old',
        originServerTs: now.subtract(const Duration(days: 31)),
        room: room,
      );
      final idle = await exporter.roomFields(room, allowed: true);

      expect(denied['sessions'], isEmpty);
      expect(denied.containsKey('notifiers'), isTrue);
      expect(idle['sessions'], isEmpty);
      expect(trimmer.calls, isEmpty);
    });

    test(
      'skips a session stored under another room or that cannot be trimmed',
      () async {
        database.put('!other:zuno.im', 's1');
        database.put(room.id, 'broken');
        exporter.sessionStored(roomId: room.id, sessionId: 's1', content: '{}');
        exporter.sessionStored(
          roomId: room.id,
          sessionId: 'broken',
          content: '{}',
        );

        final fields = await exporter.roomFields(room, allowed: true);

        expect(fields['sessions'], isEmpty);
      },
    );

    test('forgetting the account leaves nothing to export or save', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      database.put(room.id, 's1', indexes: _indexes({0: 50}));
      await exporter.rebuild(client);
      expect(exported(await exporter.roomFields(room, allowed: true)), ['s1']);

      exporter.forgetAccount();
      await exporter.save(prefs);
      final restarted = SessionExporter(trimmer: trimmer, now: () => now)
        ..load(prefs);

      expect(exporter.takeDirtyRooms(), isEmpty);
      expect(await exporter.roomFields(room, allowed: true), {
        'sessions': isEmpty,
        'notifiers': anything,
      });
      expect(
        exported(await restarted.roomFields(room, allowed: true)),
        isEmpty,
      );
    });

    test(
      'rebuilds its index from every stored session and survives a restart',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final other = buildTestRoom(client, id: '!b:zuno.im');
        database.put(room.id, 's1', indexes: _indexes({0: 50}));
        database.put(other.id, 's2');

        await exporter.rebuild(client);
        await exporter.save(prefs);
        final restarted = SessionExporter(trimmer: trimmer, now: () => now)
          ..load(prefs);

        expect(exporter.takeDirtyRooms(), {room.id, other.id});
        expect(exported(await restarted.roomFields(room, allowed: true)), [
          's1',
        ]);
        expect(exported(await restarted.roomFields(other, allowed: true)), [
          's2',
        ]);
      },
    );

    test('a restored or forwarded session never pushes the active one out, '
        'stays out of the export until it decrypts something, and then '
        'starts at what it decrypted', () async {
      database.put(room.id, 'live', indexes: _indexes({0: 1}));
      exporter.sessionIndexesUpdated(
        roomId: room.id,
        sessionId: 'live',
        previous: '{}',
        indexes: _indexes({0: 1}),
      );
      now = now.add(const Duration(minutes: 5));
      for (var i = 0; i < SessionExporter.indexedPerRoom; i++) {
        database.put(room.id, 'old$i', senderKey: 'k$i', content: _forwarded);
        exporter.sessionStored(
          roomId: room.id,
          sessionId: 'old$i',
          content: _forwarded,
        );
      }

      final restored = await exporter.roomFields(room, allowed: true);
      database.put(
        room.id,
        'old0',
        indexes: _indexes({4: 2}),
        senderKey: 'k0',
        content: _forwarded,
      );
      exporter.sessionIndexesUpdated(
        roomId: room.id,
        sessionId: 'old0',
        previous: '{}',
        indexes: _indexes({4: 2}),
      );
      final used = await exporter.roomFields(room, allowed: true);

      expect(exported(restored), ['live']);
      expect(exported(used), unorderedEquals(['live', 'old0']));
      expect(trimmer.calls.where((call) => call.startsWith('pickle-old0')), [
        'pickle-old0@4',
      ]);
    });

    int ago(Duration age) => now.subtract(age).millisecondsSinceEpoch;

    void read(
      String sessionId,
      Map<int, int> indexes, {
      String content = '{}',
    }) {
      database.put(
        room.id,
        sessionId,
        indexes: _indexes(indexes),
        content: content,
      );
      exporter.sessionIndexesUpdated(
        roomId: room.id,
        sessionId: sessionId,
        previous: '{}',
        indexes: _indexes(indexes),
      );
    }

    void storeBackupCopy(String sessionId) {
      database.put(room.id, sessionId, content: _forwarded);
      exporter.sessionStored(
        roomId: room.id,
        sessionId: sessionId,
        content: _forwarded,
      );
    }

    test('reading old messages with a restored session never puts it ahead '
        'of the sender\'s live one', () async {
      read('live', {5: ago(const Duration(minutes: 1))});
      now = now.add(const Duration(minutes: 5));
      storeBackupCopy('old');
      read('old', {4: ago(const Duration(days: 200))}, content: _forwarded);

      final fields = await exporter.roomFields(room, allowed: true);

      expect(exported(fields), ['live']);
      expect(trimmer.calls, ['pickle-live@6']);
    });

    test('a backup copy swapped in for a session never exports more of it '
        'than before, even while an old message read with it is in its '
        'grace', () async {
      read('s1', {5: ago(const Duration(minutes: 1))});
      now = now.add(const Duration(minutes: 5));
      await exporter.roomFields(room, allowed: true);
      storeBackupCopy('s1');
      read('s1', {2: ago(const Duration(days: 200))}, content: _forwarded);

      final whileReading = await exporter.roomFields(room, allowed: true);
      now = now.add(const Duration(minutes: 3));
      exporter.takeDirtyRooms();
      final afterGrace = await exporter.roomFields(room, allowed: true);

      expect(exported(whileReading), ['s1']);
      expect(exported(afterGrace), ['s1']);
      expect(trimmer.calls, ['pickle-s1@6', 'pickle-s1@6', 'pickle-s1@6']);
    });

    test('keeps a sender\'s live session exported after the SDK swaps in its '
        'backup copy, across a restart and a rebuild', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      read('previous', {9: ago(const Duration(hours: 3))});
      read('live', {5: ago(const Duration(minutes: 1))});
      now = now.add(const Duration(minutes: 5));
      final before = await exporter.roomFields(room, allowed: true);
      storeBackupCopy('live');

      final swapped = await exporter.roomFields(room, allowed: true);
      await exporter.save(prefs);
      final restarted = SessionExporter(trimmer: trimmer, now: () => now)
        ..load(prefs);
      final reloaded = await restarted.roomFields(room, allowed: true);
      await restarted.rebuild(client);
      final rebuilt = await restarted.roomFields(room, allowed: true);

      expect(exported(before), ['live']);
      expect(exported(swapped), ['live']);
      expect(exported(reloaded), ['live']);
      expect(exported(rebuilt), ['live']);
      expect(trimmer.calls, everyElement('pickle-live@6'));
    });

    test('a rebuild after an upgrade ranks sessions by their messages, not '
        'by when an older build read them', () async {
      SharedPreferences.setMockInitialValues({
        SessionExporter.indexKey: jsonEncode({
          room.id: {
            'live': ago(const Duration(minutes: 1)),
            'old': now.millisecondsSinceEpoch,
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      database.put(
        room.id,
        'live',
        indexes: _indexes({5: ago(const Duration(minutes: 1))}),
      );
      database.put(
        room.id,
        'old',
        indexes: _indexes({4: ago(const Duration(days: 200))}),
        content: _forwarded,
      );
      final upgraded = SessionExporter(trimmer: trimmer, now: () => now)
        ..load(prefs);

      await upgraded.rebuild(client);

      expect(exported(await upgraded.roomFields(room, allowed: true)), [
        'live',
      ]);
    });

    test('once synced, a rebuild leaves out rooms the account is no longer '
        'in', () async {
      final synced = _SyncedClient(database);
      synced.rooms.add(buildTestRoom(synced, id: room.id));
      database.put(room.id, 'kept', indexes: _indexes({0: 50}));
      database.put('!left:zuno.im', 'gone', indexes: _indexes({0: 50}));

      await exporter.rebuild(synced);

      expect(exporter.takeDirtyRooms(), {room.id});
    });

    test('a rebuild during the first sync keeps every session', () async {
      client.rooms.add(room);
      database.put(room.id, 'kept', indexes: _indexes({0: 50}));
      database.put('!not-yet:zuno.im', 'pending', indexes: _indexes({0: 50}));

      await exporter.rebuild(client);

      expect(exporter.takeDirtyRooms(), {room.id, '!not-yet:zuno.im'});
    });

    test('a rebuild forgets what it exported for a session the database no '
        'longer holds', () async {
      read('s1', {5: ago(const Duration(minutes: 1))});
      now = now.add(const Duration(minutes: 5));
      await exporter.roomFields(room, allowed: true);
      database.sessions.remove('s1');
      await exporter.rebuild(client);
      storeBackupCopy('s1');

      final fields = await exporter.roomFields(room, allowed: true);

      expect(fields['sessions'], isEmpty);
    });

    test('forgets when it first read an index once the grace is over, and '
        'then goes by the event time as after a restart', () async {
      final ahead = now.add(const Duration(minutes: 10)).millisecondsSinceEpoch;
      database.put(room.id, 's1', indexes: _indexes({0: 1, 1: ahead}));
      exporter.sessionIndexesUpdated(
        roomId: room.id,
        sessionId: 's1',
        previous: _indexes({0: 1}),
        indexes: _indexes({0: 1, 1: ahead}),
      );

      now = now.add(const Duration(minutes: 3));
      exporter.takeDirtyRooms();
      await exporter.roomFields(room, allowed: true);

      expect(trimmer.calls, ['pickle-s1@1']);
    });
  });

  group('with the real library', skip: _needsMacLibrary, () {
    late Map<String, dynamic> golden;

    setUpAll(() async {
      golden = pushFixture('megolm_golden_v1.json');
      if (vod.isInitialized()) return;
      await vod.init(libraryPath: _macLibrary(), stem: 'flutter_vodozemac');
    });

    test(
      'a trimmed session reads from its trim point on, as the extension will',
      () {
        final user = golden['user_id'] as String;
        final ciphertexts = (golden['ciphertexts'] as List).cast<String>();
        final plaintexts = (golden['plaintexts'] as List).cast<String>();

        final trimmed = const VodozemacMegolmTrimmer().trim(
          pickle: golden['pickle_full'] as String,
          userId: user,
          fromIndex: 3,
        )!;
        final session = vod.InboundGroupSession.fromPickleEncrypted(
          pickle: trimmed.pickle,
          pickleKey: user.toPickleKey(),
        );

        expect(trimmed.firstIndex, 3);
        expect(session.decrypt(ciphertexts[3]).plaintext, plaintexts[3]);
        expect(() => session.decrypt(ciphertexts[2]), throwsA(anything));
      },
    );

    test('the golden fixture still opens with the SDK pickle key', () {
      final user = golden['user_id'] as String;
      final session = vod.InboundGroupSession.fromPickleEncrypted(
        pickle: golden['pickle'] as String,
        pickleKey: user.toPickleKey(),
      );

      expect(session.firstKnownIndex, golden['first_index']);
      expect(
        session
            .decrypt((golden['ciphertexts'] as List)[2] as String)
            .messageIndex,
        2,
      );
    });

    test('a pickle under another key is not trimmed', () {
      expect(
        const VodozemacMegolmTrimmer().trim(
          pickle: golden['pickle_full'] as String,
          userId: '@someone:zuno.im',
          fromIndex: 0,
        ),
        isNull,
      );
    });
  });
}
