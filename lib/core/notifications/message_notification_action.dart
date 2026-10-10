import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../errors/caught_errors.dart';
import '../matrix/client_lease.dart';
import '../platform/platform_capabilities.dart';

enum MessageNotificationActionKind { reply, markRead }

typedef MessageNotificationAction = ({
  MessageNotificationActionKind kind,
  String roomId,
  String? eventId,
  String? replyText,
});

MessageNotificationAction? messageNotificationActionFrom({
  required String? actionId,
  required String? payload,
  String? input,
}) {
  final kind = switch (actionId) {
    'reply' => MessageNotificationActionKind.reply,
    'mark_read' => MessageNotificationActionKind.markRead,
    _ => null,
  };
  if (kind == null || payload == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  if (decoded['type'] != 'message') return null;
  final roomId = decoded['roomId'];
  if (roomId is! String) return null;
  final eventId = decoded['eventId'];
  return (
    kind: kind,
    roomId: roomId,
    eventId: eventId is String ? eventId : null,
    replyText: kind == MessageNotificationActionKind.reply ? input : null,
  );
}

class NotificationReplyNotSent implements Exception {
  const NotificationReplyNotSent(this.roomId);

  final String roomId;

  @override
  String toString() => 'NotificationReplyNotSent($roomId)';
}

String notificationActionTxid() =>
    'zuno-notification-${DateTime.now().microsecondsSinceEpoch}-'
    '${Random.secure().nextInt(1 << 32)}';

Future<void> replyToRoom(
  Room room,
  String text, {
  String? readEventId,
  String? txid,
}) async {
  final sent = await room.sendTextEvent(
    text,
    txid: txid,
    parseMarkdown: false,
    parseCommands: false,
  );
  if (sent == null) throw NotificationReplyNotSent(room.id);
  final eventId = readEventId;
  if (eventId == null) return;
  await runBestEffort(
    () => room.setReadMarker(eventId, mRead: eventId),
    label: 'notification reply read marker',
  );
}

Future<void> markRoomRead(Room room, String eventId) =>
    room.setReadMarker(eventId, mRead: eventId);

const headlessActionRetryDelays = [Duration(seconds: 2), Duration(seconds: 5)];

const liveHandOffPatience = Duration(seconds: 6);
const liveHandOffRetryEvery = Duration(milliseconds: 500);

const _wakeLockTimeout = Duration(seconds: 30);

final _wakeLockRunPrefix = Random().nextInt(1 << 30);
var _wakeLockRuns = 0;

class HeadlessWakeLock {
  const HeadlessWakeLock({this.capabilities, this.tag = 'message_action'});

  final PlatformCapabilities? capabilities;
  final String tag;

  static const _channel = MethodChannel('zuno/wake_lock');

  HeadlessWakeLock forRun() => HeadlessWakeLock(
    capabilities: capabilities,
    tag: '${tag}_${_wakeLockRunPrefix}_${_wakeLockRuns++}',
  );

  Future<void> acquire() => _invoke('acquire', {
    'tag': tag,
    'timeoutMs': _wakeLockTimeout.inMilliseconds,
  });

  Future<void> release() => _invoke('release', {'tag': tag});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    final supported = (capabilities ?? ambientCapabilities).headlessWakeLocks;
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e, s) {
      reportCaught('notification wake lock $method', e, s);
    }
  }
}

Future<void> runHeadlessMessageAction(
  MessageNotificationAction action, {
  required Future<Client> Function() clientBuilder,
  Future<bool> Function(MessageNotificationAction action, String txid)? handOff,
  HeadlessWakeLock wakeLock = const HeadlessWakeLock(),
  List<Duration> retryDelays = headlessActionRetryDelays,
  Duration handOffPatience = liveHandOffPatience,
  Duration handOffRetryEvery = liveHandOffRetryEvery,
}) async {
  final lock = wakeLock.forRun();
  await lock.acquire();
  final txid = notificationActionTxid();
  final handOver = handOff == null
      ? null
      : () => _handedOff(handOff, action, txid);
  Client? client;
  try {
    if (handOver != null) {
      if (await handOver()) return;
      await lock.acquire();
    }
    client = await clientOrPatientHandOff(
      clientBuilder,
      handOff: handOver,
      wakeLock: lock,
      within: handOffPatience,
      every: handOffRetryEvery,
    );
    if (client == null) return;
    final room = client.getRoomById(action.roomId);
    if (room == null) return;
    await performMessageNotificationAction(
      room,
      action,
      retryDelays: retryDelays,
      txid: txid,
    );
  } catch (e, s) {
    reportCaught('message action ${action.kind.name}', e, s);
  } finally {
    await client?.dispose(closeDatabase: false);
    await lock.release();
  }
}

Future<Client?> clientOrPatientHandOff(
  Future<Client> Function() clientBuilder, {
  required Future<bool> Function()? handOff,
  required HeadlessWakeLock wakeLock,
  Duration within = liveHandOffPatience,
  Duration every = liveHandOffRetryEvery,
}) async {
  try {
    return await clientBuilder();
  } on ClientLeaseDenied {
    if (handOff == null) rethrow;
    debugPrint('zuno/notifications: the app holds the client, handing over');
    await wakeLock.acquire();
    if (await handOffPatiently(handOff, within: within, every: every)) {
      return null;
    }
    rethrow;
  }
}

Future<bool> handOffPatiently(
  Future<bool> Function() handOff, {
  Duration within = liveHandOffPatience,
  Duration every = liveHandOffRetryEvery,
}) async {
  var spent = false;
  final deadline = Timer(within, () => spent = true);
  try {
    while (true) {
      if (await handOff()) return true;
      if (spent) return false;
      await Future<void>.delayed(every);
    }
  } finally {
    deadline.cancel();
  }
}

Future<bool> _handedOff(
  Future<bool> Function(MessageNotificationAction action, String txid) handOff,
  MessageNotificationAction action,
  String txid,
) async {
  try {
    return await handOff(action, txid);
  } catch (e, s) {
    reportCaught('message action hand-off', e, s);
    return false;
  }
}

Future<void> performMessageNotificationAction(
  Room room,
  MessageNotificationAction action, {
  List<Duration> retryDelays = headlessActionRetryDelays,
  String? txid,
}) {
  final id = txid ?? notificationActionTxid();
  return retryNotificationAction(() => _perform(room, action, id), retryDelays);
}

Map<String, Object?> encodeMessageAction(
  MessageNotificationAction action, {
  String? txid,
}) => {
  'kind': action.kind.name,
  'roomId': action.roomId,
  'eventId': action.eventId,
  'replyText': action.replyText,
  'txid': txid,
};

String? handedTxidOf(Object? message) {
  if (message is! Map) return null;
  final txid = message['txid'];
  return txid is String ? txid : null;
}

MessageNotificationAction? decodeMessageAction(Object? message) {
  if (message is! Map) return null;
  final kind = MessageNotificationActionKind.values
      .asNameMap()[message['kind']];
  final roomId = message['roomId'];
  if (kind == null || roomId is! String) return null;
  final eventId = message['eventId'];
  final replyText = message['replyText'];
  return (
    kind: kind,
    roomId: roomId,
    eventId: eventId is String ? eventId : null,
    replyText: replyText is String ? replyText : null,
  );
}

Future<void> _perform(
  Room room,
  MessageNotificationAction action,
  String txid,
) async {
  switch (action.kind) {
    case MessageNotificationActionKind.reply:
      final text = action.replyText?.trim();
      if (text == null || text.isEmpty) return;
      await replyToRoom(room, text, readEventId: action.eventId, txid: txid);
    case MessageNotificationActionKind.markRead:
      final eventId = action.eventId;
      if (eventId == null) return;
      await markRoomRead(room, eventId);
  }
}

Future<void> retryNotificationAction(
  Future<void> Function() attempt, [
  List<Duration> delays = headlessActionRetryDelays,
]) async {
  for (var i = 0; ; i++) {
    try {
      await attempt();
      return;
    } catch (e) {
      if (i >= delays.length) rethrow;
      debugPrint('zuno/notifications: action failed, retrying ($e)');
      await Future<void>.delayed(delays[i]);
    }
  }
}
