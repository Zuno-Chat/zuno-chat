import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/settings/app_preferences_provider.dart';

const _keyPrefix = 'chat.discarded_sends.';

({String txid, String? galleryId}) sendIdentity(Event event) => (
  txid: event.transactionId ?? event.eventId,
  galleryId: ownGalleryId(event, event.room.client.userID),
);

class DiscardedSends {
  DiscardedSends(this._prefs);

  final SharedPreferences _prefs;
  final _users = <String, Map<String, Set<String>>>{};
  final _sending = <String, int>{};

  bool contains(Room room, Iterable<String?> ids) {
    final discarded = _roomsOf(room)?[room.id];
    return discarded != null && ids.any(discarded.contains);
  }

  Future<void> add(Room room, String id) =>
      _update(room, (discarded) => discarded.add(id));

  Future<void> remove(Room room, String id) =>
      _update(room, (discarded) => discarded.remove(id));

  Future<void> prune(Room room, Iterable<Event> events) {
    final userId = room.client.userID;
    final unsent = <String>{};
    for (final event in events) {
      if (event.status.isSent || event.senderId != userId) continue;
      final (:txid, :galleryId) = sendIdentity(event);
      unsent.addAll([txid, ?galleryId]);
    }
    return _update(room, (discarded) {
      final before = discarded.length;
      discarded.removeWhere((id) => !unsent.contains(id) && !isSending(id));
      return discarded.length != before;
    });
  }

  Future<void> settle(Room room, Iterable<Event> events) async {
    final kept = <Event>[];
    for (final event in [...events]) {
      final (:txid, :galleryId) = sendIdentity(event);
      final dropped =
          !event.status.isSent &&
          event.senderId == room.client.userID &&
          contains(room, [txid, galleryId]) &&
          await runBestEffort(
            () => discardUnsent(event),
            label: 'discard a deleted send',
          );
      if (!dropped) kept.add(event);
    }
    await prune(room, kept);
  }

  Future<void> discardUnsent(Event event) async {
    final txid = sendIdentity(event).txid;
    if (isSending(txid)) {
      await add(event.room, txid);
      if (event.status.isError) await event.cancelSend();
    } else {
      await event.cancelSend();
      await remove(event.room, txid);
    }
  }

  bool isSending(String id) => _sending.containsKey(id);

  Future<T> whileSending<T>(
    Iterable<String?> ids,
    Future<T> Function() send,
  ) async {
    final held = ids.nonNulls.toList();
    for (final id in held) {
      _sending.update(id, (count) => count + 1, ifAbsent: () => 1);
    }
    try {
      return await send();
    } finally {
      for (final id in held) {
        final left = _sending[id]! - 1;
        if (left == 0) {
          _sending.remove(id);
        } else {
          _sending[id] = left;
        }
      }
    }
  }

  Map<String, Set<String>>? _roomsOf(Room room) {
    final userId = room.client.userID;
    if (userId == null) return null;
    return _users[userId] ??= _load(userId);
  }

  Map<String, Set<String>> _load(String userId) {
    final raw = _prefs.getString('$_keyPrefix$userId');
    if (raw == null) return {};
    try {
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, Object?>).entries)
          key: {...(value as List<Object?>).cast<String>()},
      };
    } catch (e, s) {
      reportCaught('discarded sends read', e, s);
      return {};
    }
  }

  Future<void> _update(Room room, bool Function(Set<String> ids) change) {
    final rooms = _roomsOf(room);
    if (rooms == null) return Future.value();
    final discarded = rooms[room.id] ?? <String>{};
    if (!change(discarded)) return Future.value();
    if (discarded.isEmpty) {
      rooms.remove(room.id);
    } else {
      rooms[room.id] = discarded;
    }
    final key = '$_keyPrefix${room.client.userID}';
    if (rooms.isEmpty) return _prefs.remove(key);
    return _prefs.setString(
      key,
      jsonEncode({
        for (final MapEntry(:key, :value) in rooms.entries) key: [...value],
      }),
    );
  }
}

final discardedSendsProvider = Provider((ref) {
  ref.watch(isLoggedInProvider);
  return DiscardedSends(ref.watch(sharedPreferencesProvider));
});
