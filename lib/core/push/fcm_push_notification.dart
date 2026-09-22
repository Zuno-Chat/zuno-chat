import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

PushNotification? pushNotificationFromFcmData(Map<String, dynamic> data) {
  final eventId = data['event_id'];
  final roomId = data['room_id'];
  final hasEvent =
      eventId is String &&
      eventId.isNotEmpty &&
      roomId is String &&
      roomId.isNotEmpty;
  final counts = _countsFrom(data);
  if (!hasEvent) {
    return counts == null ? null : PushNotification(counts: counts);
  }
  try {
    final parsed = PushNotification.fromJson(Map<String, Object?>.from(data));
    if (parsed.counts != null || counts == null) return parsed;
    return PushNotification(
      content: parsed.content,
      counts: counts,
      devices: parsed.devices,
      eventId: parsed.eventId,
      prio: parsed.prio,
      roomAlias: parsed.roomAlias,
      roomId: parsed.roomId,
      roomName: parsed.roomName,
      sender: parsed.sender,
      senderDisplayName: parsed.senderDisplayName,
      type: parsed.type,
    );
  } catch (e) {
    debugPrint('zuno/push: FCM payload partly unreadable ($e)');
    return PushNotification(eventId: eventId, roomId: roomId, counts: counts);
  }
}

PushNotificationCounts? _countsFrom(Map<String, dynamic> data) {
  final nested = data['counts'];
  if (nested is Map) {
    return PushNotificationCounts.fromJson(nested.cast<String, Object?>());
  }
  if (nested is String) {
    try {
      final decoded = jsonDecode(nested);
      if (decoded is Map) {
        return PushNotificationCounts.fromJson(decoded.cast<String, Object?>());
      }
    } on FormatException {
      return null;
    }
  }
  final unread = _intFrom(data['unread']);
  final missedCalls = _intFrom(data['missed_calls']);
  if (unread == null && missedCalls == null) return null;
  return PushNotificationCounts(unread: unread, missedCalls: missedCalls);
}

int? _intFrom(Object? value) => switch (value) {
  int n => n,
  String s => int.tryParse(s),
  _ => null,
};
