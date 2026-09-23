import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';

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

Future<void> replyToRoom(Room room, String text, {String? readEventId}) async {
  await room.sendTextEvent(text, parseMarkdown: false, parseCommands: false);
  final eventId = readEventId;
  if (eventId == null) return;
  await runBestEffort(
    () => room.setReadMarker(eventId, mRead: eventId),
    label: 'setReadMarker (notification reply) ${room.id}',
  );
}

Future<void> markRoomRead(Room room, String eventId) =>
    room.setReadMarker(eventId, mRead: eventId);

const headlessActionRetryDelays = [Duration(seconds: 2), Duration(seconds: 5)];

const _wakeLockTimeout = Duration(seconds: 30);
const _wakeLockTag = 'message_action';

class HeadlessWakeLock {
  const HeadlessWakeLock();

  static const _channel = MethodChannel('zuno/wake_lock');

  Future<void> acquire() => _invoke('acquire', {
    'tag': _wakeLockTag,
    'timeoutMs': _wakeLockTimeout.inMilliseconds,
  });

  Future<void> release() => _invoke('release', {'tag': _wakeLockTag});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('zuno/notifications: wake lock $method skipped ($e)');
    }
  }
}

Future<void> runHeadlessMessageAction(
  MessageNotificationAction action, {
  required Future<Client> Function() clientBuilder,
  HeadlessWakeLock wakeLock = const HeadlessWakeLock(),
  List<Duration> retryDelays = headlessActionRetryDelays,
}) async {
  await wakeLock.acquire();
  Client? client;
  try {
    client = await clientBuilder();
    final room = client.getRoomById(action.roomId);
    if (room == null) return;
    await _withRetries(() => _perform(room, action), retryDelays);
  } catch (e) {
    debugPrint('zuno/notifications: message action ${action.kind} failed: $e');
  } finally {
    await client?.dispose(closeDatabase: false);
    await wakeLock.release();
  }
}

Future<void> _perform(Room room, MessageNotificationAction action) async {
  switch (action.kind) {
    case MessageNotificationActionKind.reply:
      final text = action.replyText?.trim();
      if (text == null || text.isEmpty) return;
      await replyToRoom(room, text, readEventId: action.eventId);
    case MessageNotificationActionKind.markRead:
      final eventId = action.eventId;
      if (eventId == null) return;
      await markRoomRead(room, eventId);
  }
}

Future<void> _withRetries(
  Future<void> Function() attempt,
  List<Duration> delays,
) async {
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
