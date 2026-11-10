import '../models/voip_participant_id.dart';
import 'call_sender_key_event.dart';

class CallPeerKeys {
  static const maxHeld = 8;

  final Map<VoipParticipantId, SenderKeyMark> _applied = {};
  final Map<VoipParticipantId, SenderKey> _held = {};

  SenderKey? receive(
    VoipParticipantId id,
    SenderKey key, {
    required int? epoch,
  }) {
    if (key.epoch == epoch) return _accept(id, key);
    final held = _held.remove(id);
    if (held == null && _held.length >= maxHeld) _held.remove(_held.keys.first);
    _held[id] = held == null || _supersedes(key, markOf(held)) ? key : held;
    return null;
  }

  bool restarted(VoipParticipantId id, int epoch) {
    final applied = _applied[id];
    if (applied == null || applied.epoch == epoch) return false;
    _applied.remove(id);
    return true;
  }

  SenderKey? joined(VoipParticipantId id, int epoch) {
    final held = _held[id];
    if (held == null || held.epoch != epoch) return null;
    _held.remove(id);
    return _accept(id, held);
  }

  Set<VoipParticipantId> forgetUsers(Set<String> userIds) {
    _held.removeWhere((id, _) => userIds.contains(id.userId));
    final forgotten = {
      for (final id in _applied.keys)
        if (userIds.contains(id.userId)) id,
    };
    _applied.removeWhere((id, _) => forgotten.contains(id));
    return forgotten;
  }

  void clear() {
    _applied.clear();
    _held.clear();
  }

  SenderKey? _accept(VoipParticipantId id, SenderKey key) {
    if (!_supersedes(key, _applied[id])) return null;
    _applied[id] = markOf(key);
    return key;
  }
}

bool _supersedes(SenderKey key, SenderKeyMark? mark) =>
    mark == null || key.epoch != mark.epoch || key.gen > mark.gen;
