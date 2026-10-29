import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import '../ui/notice.dart';

const _confirmWithin = Duration(seconds: 10);

final _asked = Expando<_AskedMute>('mute asked of the server');

class _AskedMute {
  final bool muted;
  bool settled = false;
  StreamSubscription<SyncUpdate>? rulesSub;

  _AskedMute(this.muted);
}

bool isRoomMuted(Room room) => _asked[room]?.muted ?? _serverMuted(room);

@visibleForTesting
bool isRoomMuteSettling(Room room) => !(_asked[room]?.settled ?? true);

Future<void> setRoomMuted(Room room, bool muted) async {
  if (isRoomMuteSettling(room)) return;
  _forget(room);
  final asked = _asked[room] = _AskedMute(muted);
  Completer<void>? arrived;
  asked.rulesSub = room.client.onSync.stream.listen((update) {
    if (!(update.accountData?.any(_isPushRules) ?? false)) return;
    if (arrived case final waiting? when !waiting.isCompleted) {
      waiting.complete();
    }
    if (asked.settled) _forget(room, asked);
  });
  try {
    await room.setPushRuleState(
      muted ? PushRuleState.dontNotify : PushRuleState.notify,
    );
  } catch (_) {
    _forget(room, asked);
    rethrow;
  }
  if (_serverMuted(room) == muted) {
    _forget(room, asked);
    return;
  }
  try {
    await (arrived = Completer<void>()).future.timeout(_confirmWithin);
    _forget(room, asked);
  } on TimeoutException {
    asked.settled = true;
  }
}

bool _serverMuted(Room room) => room.pushRuleState == PushRuleState.dontNotify;

bool _isPushRules(BasicEvent event) => event.type == EventTypes.PushRules;

void _forget(Room room, [_AskedMute? only]) {
  final asked = _asked[room];
  if (asked == null || (only != null && !identical(asked, only))) return;
  unawaited(asked.rulesSub?.cancel());
  _asked[room] = null;
}

Future<bool> askToMuteRoom(BuildContext context, Room room, bool muted) {
  final l10n = context.l10n;
  return attempt(
    context,
    () => setRoomMuted(room, muted),
    label: muted ? 'mute' : 'unmute',
    failed: muted ? l10n.roomsNotMuted : l10n.roomsNotUnmuted,
  );
}
