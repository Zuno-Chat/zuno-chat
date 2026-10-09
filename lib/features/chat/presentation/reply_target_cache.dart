import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/undecryptable_event.dart';

const _keysArrivedDebounce = Duration(milliseconds: 300);

class ReplyTargetCache extends ChangeNotifier {
  final Future<Event?> Function(String eventId) lookup;
  final _pending = <String, Future<Event?>>{};
  final _resolved = <String, Event?>{};
  StreamSubscription<Object?>? _keysSub;
  Timer? _retryTimer;
  var _disposed = false;

  ReplyTargetCache(this.lookup, {Stream<Object?>? keysArrived}) {
    _keysSub = keysArrived?.listen((_) {
      _retryTimer?.cancel();
      _retryTimer = Timer(_keysArrivedDebounce, _retryUndecryptable);
    });
  }

  bool isResolved(String eventId) => _resolved.containsKey(eventId);

  Event? resolved(String eventId) => _resolved[eventId];

  Future<Event?> fetch(String eventId) =>
      _pending.putIfAbsent(eventId, () async {
        final event = await _lookup(eventId);
        _resolved[eventId] = event;
        return event;
      });

  Future<Event?> _lookup(String eventId) async {
    try {
      return await lookup(eventId);
    } catch (e) {
      logCaught('reply target $eventId', e);
      return null;
    }
  }

  void _retryUndecryptable() {
    final undecryptable = [
      for (final MapEntry(:key, :value) in _resolved.entries)
        if (value != null && isUndecryptableEvent(value)) key,
    ];
    for (final eventId in undecryptable) {
      unawaited(_retry(eventId));
    }
  }

  Future<void> _retry(String eventId) async {
    final event = await _lookup(eventId);
    if (_disposed || event == null || isUndecryptableEvent(event)) return;
    _resolved[eventId] = event;
    _pending[eventId] = Future.value(event);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _keysSub?.cancel();
    super.dispose();
  }
}
