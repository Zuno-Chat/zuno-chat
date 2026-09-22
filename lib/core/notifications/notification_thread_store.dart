import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const notificationThreadsKey = 'notifications.threads';
const maxNotificationLines = 8;
const _maxThreads = 32;

class NotificationLine {
  final String? eventId;
  final String senderId;
  final String senderName;
  final Uri? senderAvatarUrl;
  final String text;
  final DateTime timestamp;
  final bool placeholder;
  final String? imageUri;
  final String? imageMimeType;

  const NotificationLine({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    required this.text,
    required this.timestamp,
    this.placeholder = false,
    this.imageUri,
    this.imageMimeType,
  });

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'senderId': senderId,
    'senderName': senderName,
    'senderAvatarUrl': senderAvatarUrl?.toString(),
    'text': text,
    'ts': timestamp.toUtc().millisecondsSinceEpoch,
    'placeholder': placeholder,
    'imageUri': imageUri,
    'imageMimeType': imageMimeType,
  };

  static NotificationLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final senderId = json['senderId'];
    final text = json['text'];
    final ts = json['ts'];
    if (senderId is! String || text is! String || ts is! int) return null;
    final avatar = json['senderAvatarUrl'];
    return NotificationLine(
      eventId: json['eventId'] as String?,
      senderId: senderId,
      senderName: json['senderName'] as String? ?? senderId,
      senderAvatarUrl: avatar is String ? Uri.tryParse(avatar) : null,
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
      placeholder: json['placeholder'] == true,
      imageUri: json['imageUri'] as String?,
      imageMimeType: json['imageMimeType'] as String?,
    );
  }
}

class NotificationThread {
  final String roomId;
  final String title;
  final bool isGroupChat;
  final List<NotificationLine> lines;

  const NotificationThread({
    required this.roomId,
    required this.title,
    required this.isGroupChat,
    required this.lines,
  });

  Map<String, Object?> toJson() => {
    'title': title,
    'isGroupChat': isGroupChat,
    'lines': lines.map((l) => l.toJson()).toList(),
  };

  static NotificationThread? fromJson(String roomId, Object? json) {
    if (json is! Map) return null;
    final rawLines = json['lines'];
    return NotificationThread(
      roomId: roomId,
      title: json['title'] as String? ?? '',
      isGroupChat: json['isGroupChat'] == true,
      lines: rawLines is List
          ? rawLines.map(NotificationLine.fromJson).nonNulls.toList()
          : const [],
    );
  }
}

Map<String, Object?> _readAll(SharedPreferences prefs) {
  try {
    final decoded = jsonDecode(prefs.getString(notificationThreadsKey) ?? '');
    return decoded is Map ? decoded.cast<String, Object?>() : {};
  } catch (_) {
    return {};
  }
}

Future<void> _writeAll(SharedPreferences prefs, Map<String, Object?> all) =>
    prefs.setString(notificationThreadsKey, jsonEncode(all));

NotificationThread? readNotificationThread(
  SharedPreferences prefs,
  String roomId,
) => NotificationThread.fromJson(roomId, _readAll(prefs)[roomId]);

Future<void> writeNotificationThread(
  SharedPreferences prefs,
  NotificationThread thread,
) async {
  final all = _readAll(prefs)..remove(thread.roomId);
  final trimmed = thread.lines.length > maxNotificationLines
      ? thread.lines.sublist(thread.lines.length - maxNotificationLines)
      : thread.lines;
  all[thread.roomId] = NotificationThread(
    roomId: thread.roomId,
    title: thread.title,
    isGroupChat: thread.isGroupChat,
    lines: trimmed,
  ).toJson();
  while (all.length > _maxThreads) {
    all.remove(all.keys.first);
  }
  await _writeAll(prefs, all);
}

Future<void> clearNotificationThread(
  SharedPreferences prefs,
  String roomId,
) async {
  final all = _readAll(prefs);
  if (all.remove(roomId) == null) return;
  await _writeAll(prefs, all);
}

Future<void> clearAllNotificationThreads(SharedPreferences prefs) =>
    prefs.remove(notificationThreadsKey);
