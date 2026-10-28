import 'dart:async';

import 'package:clock/clock.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import 'redactions.dart';
import 'retry_decrypt_last_event.dart';
import 'undecryptable_event.dart';

const _lateKeyWindow = Duration(minutes: 5);
const _mostWatched = 256;

typedef _Locked = ({Event event, String sessionId, DateTime since});

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

  void _onTimelineEvent(Event event) {
    _timeline.add(event);
    if (event.type == EventTypes.Redaction) {
      if (redactionTarget(event) case final target?) _forget(target);
      return;
    }
    _watch(event);
  }

  void _watch(Event event) {
    if (!isUndecryptableEvent(event) || _client.encryption == null) return;
    final sessionId = event.content.tryGet<String>('session_id');
    if (sessionId == null) return;
    _forgetExpired();
    _locked.putIfAbsent(
      event.eventId,
      () => (event: event, sessionId: sessionId, since: clock.now()),
    );
    if (_locked.length > _mostWatched) _forget(_locked.keys.first);
    _listenForKeys(event.room);
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
    if (opened == null || !_locked.containsKey(eventId)) return;
    _forget(eventId);
    _decrypted.add(opened);
    _timeline.add(opened);
  }, label: 'late key decrypt');

  void _forgetExpired() {
    final now = clock.now();
    while (_locked.isNotEmpty) {
      final MapEntry(key: eventId, value: oldest) = _locked.entries.first;
      if (now.difference(oldest.since) <= _lateKeyWindow) return;
      _forget(eventId);
    }
  }

  void _forget(String eventId) {
    final roomId = _locked.remove(eventId)?.event.room.id;
    if (roomId == null) return;
    if (_locked.values.any((locked) => locked.event.room.id == roomId)) return;
    unawaited(_keys.remove(roomId)?.sub.cancel());
  }
}
