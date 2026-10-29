import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/matrix/late_decryptions.dart';
import '../../../core/matrix/undecryptable_event.dart';

class ReplyTargetCache extends ChangeNotifier {
  final Future<Event?> Function(String eventId) lookup;
  final _pending = <String, Future<Event?>>{};
  final _resolved = <String, Event?>{};
  StreamSubscription<Event>? _openings;
  var _disposed = false;

  ReplyTargetCache(this.lookup);

  bool isResolved(String eventId) => _resolved.containsKey(eventId);

  Event? resolved(String eventId) => _resolved[eventId];

  Future<Event?> fetch(String eventId) =>
      _pending.putIfAbsent(eventId, () async {
        final event = await _lookup(eventId);
        _resolved[eventId] = event;
        if (event != null && isUndecryptableEvent(event)) _watch(event);
        return event;
      });

  Future<Event?> _lookup(String eventId) async {
    try {
      return await lookup(eventId);
    } catch (e, s) {
      reportCaught('reply target', e, s);
      return null;
    }
  }

  void _watch(Event locked) {
    if (_disposed) return;
    final late = LateDecryptions.of(locked.room.client);
    _openings ??= late.decrypted.listen(_opened);
    late.watch(locked);
  }

  void _opened(Event opened) {
    final eventId = opened.eventId;
    final held = _resolved[eventId];
    if (held == null || !isUndecryptableEvent(held)) return;
    _resolved[eventId] = opened;
    _pending[eventId] = Future.value(opened);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_openings?.cancel());
    super.dispose();
  }
}
