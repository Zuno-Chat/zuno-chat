import 'dart:async';

import 'package:clock/clock.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import 'decrypt_again.dart';
import 'redactions.dart';
import 'undecryptable_event.dart';

const _lateKeyWindow = Duration(minutes: 5);
const _mostWatched = 256;

typedef _Locked = ({
  Event event,
  String sessionId,
  DateTime since,
  bool onTimeline,
  bool watched,
});

typedef _KeyWatch = ({Room room, StreamSubscription<String> sub});

class LateDecryptions {
  LateDecryptions._(this._client) {
    _client.onTimelineEvent.stream.listen(_onTimelineEvent);
  }

  static final _byClient = Expando<LateDecryptions>();

  static LateDecryptions of(Client client) =>
      _byClient[client] ??= LateDecryptions._(client);

  final Client _client;
  final _locked = <String, _Locked>{};
  final _keys = <String, _KeyWatch>{};
  final _decrypted = StreamController<Event>.broadcast(sync: true);
  final _timeline = StreamController<Event>.broadcast(sync: true);

  Stream<Event> get decrypted => _decrypted.stream;

  Stream<Event> get timeline => _timeline.stream;

  bool watches(String eventId) {
    _forgetExpired();
    return _locked.containsKey(eventId);
  }

  void watch(Event event) {
    if (!_lock(event, watched: true)) return;
    unawaited(_open(event.eventId));
  }

  Future<void> tryOpen(Event event) => runBestEffort(() async {
    if (!isUndecryptableEvent(event)) return;
    final opened = await decryptAgain(_client, event);
    if (opened == null || event.redacted) return;
    final onTimeline = _locked[event.eventId]?.onTimeline ?? false;
    _forget(event.eventId);
    _announce(opened, onTimeline: onTimeline);
  }, label: 'late key decrypt');

  void _onTimelineEvent(Event event) {
    _timeline.add(event);
    if (event.type == EventTypes.Redaction) {
      if (redactionTarget(event) case final target?) _forget(target);
      return;
    }
    _lock(event, onTimeline: true);
  }

  bool _lock(Event event, {bool onTimeline = false, bool watched = false}) {
    if (!isUndecryptableEvent(event) || _client.encryption == null) {
      return false;
    }
    final sessionId = event.content.tryGet<String>('session_id');
    if (sessionId == null) return false;
    _forgetExpired();
    _locked.update(
      event.eventId,
      (locked) => (
        event: locked.event,
        sessionId: locked.sessionId,
        since: locked.since,
        onTimeline: locked.onTimeline || onTimeline,
        watched: locked.watched || watched,
      ),
      ifAbsent: () => (
        event: event,
        sessionId: sessionId,
        since: clock.now(),
        onTimeline: onTimeline,
        watched: watched,
      ),
    );
    if (_locked.length > _mostWatched) _forget(_locked.keys.first);
    _listenForKeys(event.room);
    return true;
  }

  void _listenForKeys(Room room) {
    final roomId = room.id;
    final watching = _keys[roomId];
    if (identical(watching?.room, room)) return;
    unawaited(watching?.sub.cancel());
    _keys[roomId] = (
      room: room,
      sub: room.onSessionKeyReceived.stream.listen(
        (sessionId) => unawaited(_keyArrived(roomId, sessionId)),
      ),
    );
  }

  Future<void> _keyArrived(String roomId, String sessionId) async {
    _forgetExpired();
    final opening = [
      for (final MapEntry(key: eventId, value: locked) in _locked.entries)
        if (locked.event.room.id == roomId && locked.sessionId == sessionId)
          eventId,
    ];
    for (final eventId in opening) {
      await _open(eventId);
    }
  }

  Future<void> _open(String eventId) => runBestEffort(() async {
    final locked = _locked[eventId];
    if (locked == null) return;
    final opened = await decryptAgain(_client, locked.event);
    if (opened == null) return;
    final onTimeline = _locked[eventId]?.onTimeline;
    if (onTimeline == null) return;
    _forget(eventId);
    _announce(opened, onTimeline: onTimeline);
  }, label: 'late key decrypt');

  void _announce(Event opened, {required bool onTimeline}) {
    _mendLastEvent(opened);
    _decrypted.add(opened);
    if (onTimeline) _timeline.add(opened);
  }

  void _mendLastEvent(Event opened) {
    final room = opened.room;
    final last = room.lastEvent;
    if (last == null ||
        last.eventId != opened.eventId ||
        !isUndecryptableEvent(last)) {
      return;
    }
    room.lastEvent = opened;
  }

  void _forgetExpired() {
    final now = clock.now();
    final expired = <String>[];
    for (final MapEntry(key: eventId, value: locked) in _locked.entries) {
      if (locked.watched) continue;
      if (now.difference(locked.since) <= _lateKeyWindow) break;
      expired.add(eventId);
    }
    expired.forEach(_forget);
  }

  void _forget(String eventId) {
    final roomId = _locked.remove(eventId)?.event.room.id;
    if (roomId == null) return;
    if (_locked.values.any((locked) => locked.event.room.id == roomId)) return;
    unawaited(_keys.remove(roomId)?.sub.cancel());
  }
}
