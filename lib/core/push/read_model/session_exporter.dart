import 'dart:convert';
import 'dart:math';

import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/encryption/utils/stored_inbound_group_session.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;
import 'package:vodozemac/vodozemac.dart' as vod;

import '../../errors/caught_errors.dart';
import '../../matrix/database_compaction.dart';
import '../../matrix/ephemeral_to_device.dart';
import 'mention_spec.dart';

abstract interface class InboundSessionEvents {
  void sessionStored({
    required String roomId,
    required String sessionId,
    required String content,
  });

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
      inboundSessionEvents.sessionStored(
        roomId: roomId,
        sessionId: sessionId,
        content: content,
      );
    } catch (e, s) {
      reportCaughtType('nse session stored hook', e, s);
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
    } catch (e, s) {
      reportCaughtType('nse session indexes hook', e, s);
    }
  }
}

class SessionExportingDatabase extends MatrixSdkDatabase
    with
        InboundSessionHooks,
        EphemeralToDeviceStorage,
        CompactsAfterCacheClear {
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
    } catch (e, s) {
      reportCaught('nse session trim', e, s);
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
  } on FormatException {
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

bool _isForwarded(String content) {
  try {
    final decoded = jsonDecode(content);
    return decoded is Map &&
        decoded.containsKey('forwarding_curve25519_key_chain');
  } on FormatException {
    return false;
  }
}

int? trimPoint({
  required Map<int, int> decrypted,
  required Map<int, DateTime> firstSeen,
  required DateTime now,
  int? exportedFrom,
  Duration grace = SessionExporter.grace,
}) {
  int? lowest;
  int? highestRead;
  for (final MapEntry(key: index, value: eventTs) in decrypted.entries) {
    if (lowest == null || index < lowest) lowest = index;
    final seen =
        firstSeen[index] ??
        (eventTs > 0 ? DateTime.fromMillisecondsSinceEpoch(eventTs) : null);
    if (seen != null && now.difference(seen) < grace) continue;
    if (highestRead == null || index > highestRead) highestRead = index;
  }
  final start = highestRead == null ? lowest : highestRead + 1;
  if (start == null || exportedFrom == null) return start ?? exportedFrom;
  return max(start, exportedFrom);
}

int _newestEvent(Map<int, int> decrypted) => decrypted.values.fold(0, max);

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
  static const exportedKey = 'nse.session_exported_from';

  final MegolmTrimmer _trimmer;
  final DateTime Function() _now;
  final _dirty = <String>{};
  final _firstSeen = <String, Map<int, DateTime>>{};
  final _graceUntil = <String, DateTime>{};
  final _index = <String, Map<String, int>>{};
  final _exportedFrom = <String, Map<String, int>>{};
  final _sessions = <String, List<Map<String, Object?>>>{};
  final _changes = <String, int>{};
  var _epoch = 0;
  void Function()? onDirty;

  @override
  void sessionStored({
    required String roomId,
    required String sessionId,
    required String content,
  }) {
    final recency = _isForwarded(content) ? 0 : _now().millisecondsSinceEpoch;
    _remember(roomId, sessionId, recency);
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
    final decrypted = decryptedIndexes(indexes);
    final known = decryptedIndexes(previous).keys.toSet();
    final seen = _firstSeen.putIfAbsent(sessionId, () => {});
    for (final index in decrypted.keys) {
      if (!known.contains(index)) seen.putIfAbsent(index, () => now);
    }
    _graceUntil[roomId] = now.add(grace);
    _remember(roomId, sessionId, _newestEvent(decrypted));
    _changed(roomId);
  }

  Set<String> takeDirtyRooms() {
    final now = _now();
    _firstSeen.removeWhere((_, seen) {
      seen.removeWhere((_, at) => now.difference(at) >= grace);
      return seen.isEmpty;
    });
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

  void forgetAccount() {
    _dirty.clear();
    _firstSeen.clear();
    _graceUntil.clear();
    _index.clear();
    _exportedFrom.clear();
    _sessions.clear();
    _changes.clear();
    _epoch++;
  }

  void load(SharedPreferences prefs) {
    final index = _stored(prefs, indexKey);
    for (final MapEntry(key: roomId, value: sessions) in index.entries) {
      for (final MapEntry(key: sessionId, value: at) in sessions.entries) {
        _remember(roomId, sessionId, at);
      }
    }
    _restoreExported(_stored(prefs, exportedKey));
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(indexKey, jsonEncode(_index));
    await prefs.setString(exportedKey, jsonEncode(_exportedFrom));
  }

  Future<void> rebuild(Client client) async {
    final sessions = await client.database.getAllInboundGroupSessions();
    final recency = {..._index};
    final exportedFrom = {..._exportedFrom};
    _index.clear();
    _exportedFrom.clear();
    _sessions.clear();
    _epoch++;
    final joined = client.prevBatch == null
        ? null
        : {
            for (final room in client.rooms)
              if (room.membership == Membership.join) room.id,
          };
    for (final session in sessions) {
      if (joined != null && !joined.contains(session.roomId)) continue;
      final decrypted = decryptedIndexes(session.indexes);
      _remember(
        session.roomId,
        session.sessionId,
        decrypted.isEmpty
            ? (recency[session.roomId]?[session.sessionId] ?? 0)
            : _newestEvent(decrypted),
      );
    }
    _restoreExported(exportedFrom);
    _dirty.addAll(_index.keys);
    onDirty?.call();
  }

  Map<String, Map<String, int>> _stored(SharedPreferences prefs, String key) {
    final Object? decoded;
    try {
      decoded = jsonDecode(prefs.getString(key) ?? '{}');
    } on FormatException {
      return const {};
    } catch (e, s) {
      reportCaught('nse session index load', e, s);
      return const {};
    }
    if (decoded is! Map) return const {};
    return {
      for (final MapEntry(key: roomId, value: sessions) in decoded.entries)
        if (roomId is String && sessions is Map)
          roomId: {
            for (final MapEntry(key: sessionId, value: number)
                in sessions.entries)
              if (sessionId is String && number is int) sessionId: number,
          },
    };
  }

  void _restoreExported(Map<String, Map<String, int>> exportedFrom) {
    for (final MapEntry(key: roomId, value: sessions) in exportedFrom.entries) {
      for (final MapEntry(key: sessionId, value: firstIndex)
          in sessions.entries) {
        _exported(roomId, sessionId, firstIndex);
      }
    }
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
    } catch (e, s) {
      reportCaughtType('nse room export', e, s);
      return fields(const []);
    }
  }

  Future<List<Map<String, Object?>>> _trimmed(Room room, String userId) async {
    final owners = _owners(room.client);
    final stored = <String, StoredInboundGroupSession>{};
    final candidates = <SessionCandidate>[];
    for (final MapEntry(key: sessionId, value: recencyMs) in [
      ...?_index[room.id]?.entries,
    ]) {
      final session = await room.client.database.getInboundGroupSession(
        room.id,
        sessionId,
      );
      if (session == null || session.roomId != room.id) continue;
      final decrypted = decryptedIndexes(session.indexes);
      final forwarded = _isForwarded(session.content);
      final exportedFrom = _exportedFrom[room.id]?[sessionId];
      if (decrypted.isEmpty && forwarded && exportedFrom == null) continue;
      stored[sessionId] = session;
      candidates.add(
        SessionCandidate(
          sessionId: sessionId,
          senderKey: session.senderKey,
          recencyMs: max(_newestEvent(decrypted), recencyMs),
          used: decrypted.isNotEmpty || forwarded,
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
        exportedFrom: _exportedFrom[room.id]?[sessionId],
      );
      final trimmed = _trimmer.trim(
        pickle: session.pickle,
        userId: userId,
        fromIndex: start ?? 0,
      );
      if (trimmed == null) continue;
      _exported(room.id, sessionId, trimmed.firstIndex);
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
    _exportedFrom[roomId]?.remove(oldest.key);
  }

  void _exported(String roomId, String sessionId, int firstIndex) {
    if (_index[roomId]?.containsKey(sessionId) != true) return;
    final exported = _exportedFrom.putIfAbsent(roomId, () => {});
    exported[sessionId] = max(exported[sessionId] ?? firstIndex, firstIndex);
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
