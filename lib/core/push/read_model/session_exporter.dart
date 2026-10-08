import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/encryption/utils/stored_inbound_group_session.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;
import 'package:vodozemac/vodozemac.dart' as vod;

import '../../matrix/ephemeral_to_device.dart';
import 'mention_spec.dart';

abstract interface class InboundSessionEvents {
  void sessionStored({required String roomId, required String sessionId});

  void sessionIndexesUpdated({
    required String roomId,
    required String sessionId,
    required String? previous,
    required String indexes,
  });
}

mixin InboundSessionHooks on DatabaseApi {
  InboundSessionEvents get inboundSessionEvents;

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
    await super.storeInboundGroupSession(
      roomId,
      sessionId,
      pickle,
      content,
      indexes,
      allowedAtIndex,
      senderKey,
      senderClaimedKey,
    );
    try {
      inboundSessionEvents.sessionStored(roomId: roomId, sessionId: sessionId);
    } catch (e) {
      debugPrint('zuno/nse: a stored session was not noted (${e.runtimeType})');
    }
  }

  @override
  Future<void> updateInboundGroupSessionIndexes(
    String indexes,
    String roomId,
    String sessionId,
  ) async {
    final before = await getInboundGroupSession(roomId, sessionId);
    await super.updateInboundGroupSessionIndexes(indexes, roomId, sessionId);
    try {
      inboundSessionEvents.sessionIndexesUpdated(
        roomId: roomId,
        sessionId: sessionId,
        previous: before?.indexes,
        indexes: indexes,
      );
    } catch (e) {
      debugPrint('zuno/nse: a read index was not noted (${e.runtimeType})');
    }
  }
}

class SessionExportingDatabase extends MatrixSdkDatabase
    with InboundSessionHooks, EphemeralToDeviceStorage {
  SessionExportingDatabase(
    super.name, {
    super.database,
    required this.inboundSessionEvents,
  }) : super.buildWithoutOpen();

  @override
  final InboundSessionEvents inboundSessionEvents;
}

Future<SessionExportingDatabase> openSessionExportingDatabase(
  sqflite.Database database,
) async {
  final exporting = SessionExportingDatabase(
    'zuno',
    database: database,
    inboundSessionEvents: SessionExporter.instance,
  );
  await exporting.open();
  return exporting;
}

class TrimmedSession {
  const TrimmedSession({required this.pickle, required this.firstIndex});

  final String pickle;
  final int firstIndex;
}

abstract interface class MegolmTrimmer {
  TrimmedSession? trim({
    required String pickle,
    required String userId,
    required int fromIndex,
  });
}

class VodozemacMegolmTrimmer implements MegolmTrimmer {
  const VodozemacMegolmTrimmer();

  @override
  TrimmedSession? trim({
    required String pickle,
    required String userId,
    required int fromIndex,
  }) {
    try {
      final key = userId.toPickleKey();
      final session = vod.InboundGroupSession.fromPickleEncrypted(
        pickle: pickle,
        pickleKey: key,
      );
      final exported = session.exportAt(
        max(session.firstKnownIndex, fromIndex),
      );
      if (exported == null) return null;
      final trimmed = vod.InboundGroupSession.import(exported);
      return TrimmedSession(
        pickle: trimmed.toPickleEncrypted(key),
        firstIndex: trimmed.firstKnownIndex,
      );
    } catch (e) {
      debugPrint('zuno/nse: a session could not be trimmed ($e)');
      return null;
    }
  }
}

class SessionCandidate {
  const SessionCandidate({
    required this.sessionId,
    required this.senderKey,
    required this.recencyMs,
    required this.used,
  });

  final String sessionId;
  final String senderKey;
  final int recencyMs;
  final bool used;
}

List<String> selectSessions(
  Iterable<SessionCandidate> candidates, {
  int limit = SessionExporter.maxPerRoom,
}) {
  final newestPerDevice = <String, SessionCandidate>{};
  final unused = <SessionCandidate>[];
  for (final candidate in candidates) {
    if (!candidate.used) {
      unused.add(candidate);
      continue;
    }
    final known = newestPerDevice[candidate.senderKey];
    if (known == null || candidate.recencyMs > known.recencyMs) {
      newestPerDevice[candidate.senderKey] = candidate;
    }
  }
  final chosen = [...newestPerDevice.values, ...unused]
    ..sort((a, b) => b.recencyMs.compareTo(a.recencyMs));
  return [for (final candidate in chosen.take(limit)) candidate.sessionId];
}

Map<int, int> decryptedIndexes(String? indexes) {
  if (indexes == null) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(indexes);
  } catch (_) {
    return const {};
  }
  if (decoded is! Map) return const {};
  final result = <int, int>{};
  for (final MapEntry(:key, :value) in decoded.entries) {
    final index = key is String && key.startsWith('key-')
        ? int.tryParse(key.substring(4))
        : null;
    if (index == null) continue;
    result[index] = value is String
        ? int.tryParse(value.split('|').last) ?? 0
        : 0;
  }
  return result;
}

int? trimPoint({
  required Map<int, int> decrypted,
  required Map<int, DateTime> firstSeen,
  required DateTime now,
  Duration grace = SessionExporter.grace,
}) {
  int? highest;
  for (final MapEntry(key: index, value: eventTs) in decrypted.entries) {
    final seen =
        firstSeen[index] ??
        (eventTs > 0 ? DateTime.fromMillisecondsSinceEpoch(eventTs) : null);
    if (seen != null && now.difference(seen) < grace) continue;
    if (highest == null || index > highest) highest = index;
  }
  return highest == null ? null : highest + 1;
}

class SessionExporter implements InboundSessionEvents {
  SessionExporter({
    this._trimmer = const VodozemacMegolmTrimmer(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final instance = SessionExporter();

  static const maxPerRoom = 8;
  static const indexedPerRoom = 16;
  static const grace = Duration(minutes: 2);
  static const idleAfter = Duration(days: 30);
  static const indexKey = 'nse.session_index';

  final MegolmTrimmer _trimmer;
  final DateTime Function() _now;
  final _dirty = <String>{};
  final _firstSeen = <String, Map<int, DateTime>>{};
  final _graceUntil = <String, DateTime>{};
  final _index = <String, Map<String, int>>{};
  final _sessions = <String, List<Map<String, Object?>>>{};
  final _changes = <String, int>{};
  var _epoch = 0;
  void Function()? onDirty;

  @override
  void sessionStored({required String roomId, required String sessionId}) {
    _remember(roomId, sessionId, _now().millisecondsSinceEpoch);
    _changed(roomId);
  }

  @override
  void sessionIndexesUpdated({
    required String roomId,
    required String sessionId,
    required String? previous,
    required String indexes,
  }) {
    final now = _now();
    final known = decryptedIndexes(previous).keys.toSet();
    final seen = _firstSeen.putIfAbsent(sessionId, () => {});
    for (final index in decryptedIndexes(indexes).keys) {
      if (!known.contains(index)) seen.putIfAbsent(index, () => now);
    }
    _graceUntil[roomId] = now.add(grace);
    _remember(roomId, sessionId, now.millisecondsSinceEpoch);
    _changed(roomId);
  }

  Set<String> takeDirtyRooms() {
    final now = _now();
    final expired = [
      for (final MapEntry(:key, :value) in _graceUntil.entries)
        if (!now.isBefore(value)) key,
    ];
    for (final roomId in expired) {
      _graceUntil.remove(roomId);
      _invalidate(roomId);
    }
    final rooms = {..._dirty, ...expired};
    _dirty.clear();
    return rooms;
  }

  Set<String> get indexedRooms => _index.keys.toSet();

  void load(SharedPreferences prefs) {
    final Object? decoded;
    try {
      decoded = jsonDecode(prefs.getString(indexKey) ?? '{}');
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    for (final MapEntry(:key, :value) in decoded.entries) {
      if (key is! String || value is! Map) continue;
      for (final MapEntry(key: sessionId, value: at) in value.entries) {
        if (sessionId is String && at is int) _remember(key, sessionId, at);
      }
    }
  }

  Future<void> save(SharedPreferences prefs) =>
      prefs.setString(indexKey, jsonEncode(_index));

  Future<void> rebuild(Client client) async {
    final sessions = await client.database.getAllInboundGroupSessions();
    _index.clear();
    _sessions.clear();
    _epoch++;
    for (final session in sessions) {
      final decrypted = decryptedIndexes(session.indexes);
      _remember(
        session.roomId,
        session.sessionId,
        decrypted.values.fold(0, max),
      );
    }
    _dirty.addAll(_index.keys);
    onDirty?.call();
  }

  Future<Map<String, Object?>> roomFields(
    Room room, {
    required bool allowed,
  }) async {
    final notifiers = roomNotifiers(room);
    Map<String, Object?> fields(List<Object?> sessions) => {
      'sessions': sessions,
      'notifiers': notifiers,
    };
    final userId = room.client.userID;
    if (!allowed || userId == null || _excluded(room)) return fields(const []);
    final cached = _sessions[room.id];
    if (cached != null) return fields(cached);
    final stamp = _stamp(room.id);
    try {
      final sessions = await _trimmed(room, userId);
      if (_stamp(room.id) == stamp) _sessions[room.id] = sessions;
      return fields(sessions);
    } catch (e) {
      debugPrint('zuno/nse: a room could not be exported (${e.runtimeType})');
      return fields(const []);
    }
  }

  Future<List<Map<String, Object?>>> _trimmed(Room room, String userId) async {
    final owners = _owners(room.client);
    final stored = <String, StoredInboundGroupSession>{};
    final candidates = <SessionCandidate>[];
    for (final MapEntry(key: sessionId, value: addedMs) in [
      ...?_index[room.id]?.entries,
    ]) {
      final session = await room.client.database.getInboundGroupSession(
        room.id,
        sessionId,
      );
      if (session == null || session.roomId != room.id) continue;
      stored[sessionId] = session;
      final decrypted = decryptedIndexes(session.indexes);
      candidates.add(
        SessionCandidate(
          sessionId: sessionId,
          senderKey: session.senderKey,
          recencyMs: decrypted.values.fold(addedMs, max),
          used: decrypted.isNotEmpty,
        ),
      );
    }
    final sessions = <Map<String, Object?>>[];
    for (final sessionId in selectSessions(candidates)) {
      final session = stored[sessionId]!;
      final start = trimPoint(
        decrypted: decryptedIndexes(session.indexes),
        firstSeen: _firstSeen[sessionId] ?? const {},
        now: _now(),
      );
      final trimmed = _trimmer.trim(
        pickle: session.pickle,
        userId: userId,
        fromIndex: start ?? 0,
      );
      if (trimmed == null) continue;
      sessions.add({
        'session_id': sessionId,
        'sender': ?owners[session.senderKey],
        'sender_key': session.senderKey,
        'first_index': trimmed.firstIndex,
        'pickle': trimmed.pickle,
      });
    }
    return sessions;
  }

  bool _excluded(Room room) {
    if (room.pushRuleState == PushRuleState.dontNotify) return true;
    final last = room.lastEvent?.originServerTs;
    return last != null && _now().difference(last) > idleAfter;
  }

  Map<String, String> _owners(Client client) {
    final owners = <String, String>{};
    for (final list in client.userDeviceKeys.values) {
      for (final device in list.deviceKeys.values) {
        final key = device.curve25519Key;
        if (key != null) owners[key] = list.userId;
      }
    }
    return owners;
  }

  void _remember(String roomId, String sessionId, int recencyMs) {
    final sessions = _index.putIfAbsent(roomId, () => {});
    sessions[sessionId] = max(sessions[sessionId] ?? 0, recencyMs);
    if (sessions.length <= indexedPerRoom) return;
    final oldest = sessions.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    sessions.remove(oldest.key);
  }

  (int, int) _stamp(String roomId) => (_epoch, _changes[roomId] ?? 0);

  void _invalidate(String roomId) {
    _changes[roomId] = (_changes[roomId] ?? 0) + 1;
    _sessions.remove(roomId);
  }

  void _changed(String roomId) {
    _invalidate(roomId);
    _dirty.add(roomId);
    onDirty?.call();
  }
}
