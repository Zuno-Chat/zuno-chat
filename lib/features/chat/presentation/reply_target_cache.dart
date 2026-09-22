import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';

class ReplyTargetCache {
  final Future<Event?> Function(String eventId) lookup;
  final _pending = <String, Future<Event?>>{};
  final _resolved = <String, Event?>{};

  ReplyTargetCache(this.lookup);

  bool isResolved(String eventId) => _resolved.containsKey(eventId);

  Event? resolved(String eventId) => _resolved[eventId];

  Future<Event?> fetch(String eventId) =>
      _pending.putIfAbsent(eventId, () async {
        Event? event;
        try {
          event = await lookup(eventId);
        } catch (e) {
          logCaught('reply target $eventId', e);
        }
        _resolved[eventId] = event;
        return event;
      });
}
