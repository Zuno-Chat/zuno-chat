import 'dart:async';

import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../errors/caught_errors.dart';
import 'message_notification_action.dart';
import 'native_notification_actions.dart';
import 'notification_action_target.dart';

typedef MessageActionPerformer = Future<void> Function(
  Room room,
  MessageNotificationAction action,
  String txid,
);

typedef MarkReadEventFinder = Future<String?> Function(
  Room room,
  NativeNotificationAction action,
);

typedef _Outcome = ({bool ok, Future<void> Function()? followUp});

const nativeActionBudget = Duration(seconds: 18);
const _readAfterReplyBudget = Duration(seconds: 3);
const _failed = (ok: false, followUp: null);

class NativeNotificationActionRunner {
  NativeNotificationActionRunner({
    NativeNotificationActionsChannel? channel,
    ThreadKeyRooms? rooms,
    MarkReadEventFinder? markReadEvent,
    MessageActionPerformer? perform,
    Duration budget = nativeActionBudget,
    this._wakeLock = const HeadlessWakeLock(tag: 'action_follow_up'),
  }) : _channel = channel ?? NativeNotificationActionsChannel(),
       _rooms = rooms ?? ThreadKeyRooms(),
       _markReadEvent = markReadEvent ?? _markReadEventIn,
       _perform = perform ?? _performWithOneRetry,
       _actionBudget = budget;

  final NativeNotificationActionsChannel _channel;
  final ThreadKeyRooms _rooms;
  final MarkReadEventFinder _markReadEvent;
  final MessageActionPerformer _perform;
  final Duration _actionBudget;
  final HeadlessWakeLock _wakeLock;
  Client? _client;
  Future<void> _running = Future<void>.value();

  void attach(Client client) {
    if (!_channel.enabled) return;
    _client = client;
    _channel.listen(() => unawaited(drain()));
    unawaited(drain());
  }

  Future<void> drain() {
    _running = _running.then(
      (_) => runBestEffort(_drainOnce, label: 'native actions drain'),
    );
    return _running;
  }

  Future<void> _drainOnce() async {
    final client = _client;
    if (client == null) return;
    final batch = await _channel.take();
    for (final id in batch.unreadable) {
      await _channel.finish(id, ok: false);
    }
    for (final action in batch.actions) {
      final (:ok, :followUp) = await _run(client, action);
      if (followUp == null) {
        await _channel.finish(action.id, ok: ok);
        continue;
      }
      final hold = _wakeLock.forRun();
      await hold.acquire();
      await _channel.finish(action.id, ok: ok);
      unawaited(_followUpUnder(hold, followUp));
    }
  }

  Future<void> _followUpUnder(
    HeadlessWakeLock hold,
    Future<void> Function() followUp,
  ) async {
    try {
      await followUp();
    } finally {
      await hold.release();
    }
  }

  Future<_Outcome> _run(Client client, NativeNotificationAction action) async {
    try {
      if (!client.isLogged()) return _failed;
      final room = await _roomFor(client, action);
      if (room == null) return _failed;
      final txid = 'zuno-notification-${action.id}';
      if (action.kind == NativeNotificationActionKind.markRead) {
        return (
          ok: await _markRead(room, action, txid).timeout(_actionBudget),
          followUp: null,
        );
      }
      await _perform(room, (
        kind: MessageNotificationActionKind.reply,
        roomId: room.id,
        eventId: null,
        replyText: action.replyText,
      ), txid).timeout(_actionBudget);
      return (ok: true, followUp: () => _markReadAfterReply(room, action));
    } catch (e, s) {
      reportCaught('native ${action.kind.name} action', e, s);
      return _failed;
    }
  }

  Future<bool> _markRead(
    Room room,
    NativeNotificationAction action,
    String txid,
  ) async {
    final eventId = await _markReadEvent(room, action);
    if (eventId == null) return false;
    await _perform(room, (
      kind: MessageNotificationActionKind.markRead,
      roomId: room.id,
      eventId: eventId,
      replyText: null,
    ), txid);
    return true;
  }

  Future<void> _markReadAfterReply(
    Room room,
    NativeNotificationAction action,
  ) async {
    try {
      final eventId = await _markReadEvent(
        room,
        action,
      ).timeout(_readAfterReplyBudget);
      if (eventId == null) return;
      await markRoomRead(room, eventId).timeout(_readAfterReplyBudget);
    } catch (e, s) {
      reportCaught('native read marker after reply', e, s);
    }
  }

  Future<Room?> _roomFor(Client client, NativeNotificationAction action) async {
    final roomId = action.roomId;
    if (roomId != null) return client.getRoomById(roomId);
    final token = action.roomToken;
    return token == null ? null : _rooms.roomFor(client, token);
  }
}

Future<String?> _markReadEventIn(Room room, NativeNotificationAction action) =>
    markReadEventIn(
      room,
      eventId: action.eventId,
      eventSeconds: action.eventSeconds,
    );

Future<void> _performWithOneRetry(
  Room room,
  MessageNotificationAction action,
  String txid,
) => performMessageNotificationAction(
  room,
  action,
  retryDelays: const [Duration(seconds: 2)],
  txid: txid,
);

final nativeNotificationActionRunner = NativeNotificationActionRunner();
