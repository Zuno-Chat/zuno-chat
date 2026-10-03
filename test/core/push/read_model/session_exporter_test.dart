import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/encryption/utils/stored_inbound_group_session.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/push/read_model/session_exporter.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

class _Events implements InboundSessionEvents {
  final stored = <String>[];
  final updated = <(String, String?, String)>[];

  @override
  void sessionStored({required String roomId, required String sessionId}) =>
      stored.add('$roomId/$sessionId');

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
  void sessionStored({required String roomId, required String sessionId}) =>
      throw StateError('listener');

  @override
  void sessionIndexesUpdated({
    required String roomId,
    required String sessionId,
    required String? previous,
    required String indexes,
  }) => throw StateError('listener');
}

class _SessionsDatabase extends FakeDatabaseApi {
  final sessions = <String, StoredInboundGroupSession>{};
  bool failWrites = false;
  bool failReads = false;
  void Function()? duringRead;

  StoredInboundGroupSession put(
    String roomId,
    String sessionId, {
    String indexes = '{}',
    String senderKey = 'curve-a',
  }) => sessions[sessionId] = StoredInboundGroupSession(
    roomId: roomId,
    sessionId: sessionId,
    pickle: 'pickle-$sessionId',
    content: '{}',
    indexes: indexes,
    allowedAtIndex: '{}',
    senderKey: senderKey,
    senderClaimedKeys: '{}',
  );

  @override
  Future<StoredInboundGroupSession?> getInboundGroupSession(
    String roomId,
    String sessionId,
  ) async {
    if (failReads) throw StateError('unreadable');
    duringRead?.call();
    return sessions[sessionId];
  }

  @override
  Future<List<StoredInboundGroupSession>> getAllInboundGroupSessions() async =>
      sessions.values.toList();

  @override
  Future<void> storeInboundGroupSession(
    String roomId,
    String sessionId,
    String pickle,
    String content,
    String indexes,
    String allowedAtIndex,
    String senderKey,
    String senderClaimedKey,
  ) async {
    if (failWrites) throw StateError('disk full');
    put(roomId, sessionId, indexes: indexes, senderKey: senderKey);
  }

  @override
  Future<void> updateInboundGroupSessionIndexes(
    String indexes,
    String roomId,
    String sessionId,
  ) async {
    if (failWrites) throw StateError('disk full');
    put(roomId, sessionId, indexes: indexes);
  }
}

class _HookedDatabase extends _SessionsDatabase with InboundSessionHooks {
  _HookedDatabase(this.inboundSessionEvents);

  @override
  final InboundSessionEvents inboundSessionEvents;
}

class _Trimmer implements MegolmTrimmer {
  final calls = <String>[];

  @override
  TrimmedSession? trim({
    required String pickle,
    required String userId,
    required int fromIndex,
  }) {
    calls.add('$pickle@$fromIndex');
    if (pickle == 'pickle-broken') return null;
    return TrimmedSession(pickle: 'trimmed-$pickle', firstIndex: fromIndex);
  }
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
    Future<void> storeSession(_HookedDatabase database) => database
        .storeInboundGroupSession('!r', 's1', 'p', '{}', '{}', '{}', 'k', '{}');

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

        expect(events.stored, ['!r/s1']);
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

    test('is the first known index while nothing is old enough', () {
      expect(
        trimPoint(decrypted: {7: 0}, firstSeen: {7: now}, now: now),
        isNull,
      );
      expect(
        trimPoint(decrypted: const {}, firstSeen: const {}, now: now),
        isNull,
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
    late _SessionsDatabase database;
    late Client client;
    late Room room;
    late _Trimmer trimmer;
    late SessionExporter exporter;

    setUp(() {
      now = DateTime(2026, 10, 2, 12);
      database = _SessionsDatabase();
      client = buildTestClient(userId: '@mwong:zuno.im', database: database);
      room = buildTestRoom(client, id: '!r:zuno.im');
      trimmer = _Trimmer();
      exporter = SessionExporter(trimmer: trimmer, now: () => now);
    });

    test(
      'marks a room dirty for a new session and trims it from its start',
      () async {
        database.put(room.id, 's1');
        exporter.sessionStored(roomId: room.id, sessionId: 's1');

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
        exporter.sessionStored(roomId: room.id, sessionId: 's1');
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
      exporter.sessionStored(roomId: room.id, sessionId: 's1');

      await exporter.roomFields(room, allowed: true);
      await exporter.roomFields(room, allowed: true);
      exporter.sessionStored(roomId: room.id, sessionId: 's1');
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
      exporter.sessionStored(roomId: room.id, sessionId: 's1');
      exporter.sessionStored(roomId: room.id, sessionId: 's2');
      database.duringRead = () {
        database.duringRead = null;
        database.put(room.id, 's3');
        exporter.sessionStored(roomId: room.id, sessionId: 's3');
      };

      final during = await exporter.roomFields(room, allowed: true);
      final after = await exporter.roomFields(room, allowed: true);

      expect(exported(during), containsAll(['s1', 's2']));
      expect(exported(after), containsAll(['s1', 's2', 's3']));
    });

    test('a read that fails exports nothing for the room and is tried again '
        'next time', () async {
      database.put(room.id, 's1');
      exporter.sessionStored(roomId: room.id, sessionId: 's1');
      database.failReads = true;

      final failed = await exporter.roomFields(room, allowed: true);
      database.failReads = false;
      final retried = await exporter.roomFields(room, allowed: true);

      expect(failed['sessions'], isEmpty);
      expect(failed.containsKey('notifiers'), isTrue);
      expect(exported(retried), ['s1']);
    });

    test('exports nothing when not allowed, muted or idle, but still names notifiers', () async {
      database.put(room.id, 's1');
      exporter.sessionStored(roomId: room.id, sessionId: 's1');

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
        exporter.sessionStored(roomId: room.id, sessionId: 's1');
        exporter.sessionStored(roomId: room.id, sessionId: 'broken');

        final fields = await exporter.roomFields(room, allowed: true);

        expect(fields['sessions'], isEmpty);
      },
    );

    test(
      'rebuilds its index from every stored session and survives a restart',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        database.put(room.id, 's1', indexes: _indexes({0: 50}));
        database.put('!b:zuno.im', 's2');

        await exporter.rebuild(client);
        await exporter.save(prefs);
        final restarted = SessionExporter(trimmer: trimmer, now: () => now)
          ..load(prefs);

        expect(exporter.takeDirtyRooms(), {room.id, '!b:zuno.im'});
        expect(restarted.indexedRooms, {room.id, '!b:zuno.im'});
      },
    );
  });

  group('with the real library', skip: _needsMacLibrary, () {
    late Map<String, dynamic> golden;

    setUpAll(() async {
      golden = jsonDecode(
        File('test/fixtures/push/megolm_golden_v1.json').readAsStringSync(),
      ) as Map<String, dynamic>;
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
