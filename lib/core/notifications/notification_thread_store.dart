import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../errors/caught_errors.dart';
import 'notification_ids.dart';

const notificationThreadsKey = 'notifications.threads';
const maxNotificationLines = 8;
const maxNotificationThreads = 32;

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
  final bool quiet;

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
    this.quiet = false,
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
    'quiet': quiet,
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
      quiet: json['quiet'] == true,
    );
  }
}

class NotificationThread {
  final String key;
  final String roomId;
  final String title;
  final bool isGroupChat;
  final List<NotificationLine> lines;

  const NotificationThread({
    required this.roomId,
    String? key,
    required this.title,
    required this.isGroupChat,
    required this.lines,
  }) : key = key ?? roomId;

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'title': title,
    'isGroupChat': isGroupChat,
    'lines': lines.map((l) => l.toJson()).toList(),
  };

  static NotificationThread? fromJson(String key, Object? json) {
    if (json is! Map) return null;
    final rawLines = json['lines'];
    final roomId = json['roomId'];
    return NotificationThread(
      key: key,
      roomId: roomId is String ? roomId : key,
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
  } on FormatException {
    return {};
  } catch (e, s) {
    reportCaught('notification threads read', e, s);
    return {};
  }
}

Future<void> _writeAll(SharedPreferences prefs, Map<String, Object?> all) =>
    prefs.setString(notificationThreadsKey, jsonEncode(all));

NotificationThread? readNotificationThread(
  SharedPreferences prefs,
  String key,
) => NotificationThread.fromJson(key, _readAll(prefs)[key]);

Future<void> writeNotificationThread(
  SharedPreferences prefs,
  NotificationThread thread, {
  Set<int> showing = const {},
}) async {
  final all = _readAll(prefs)..remove(thread.key);
  final trimmed = thread.lines.length > maxNotificationLines
      ? thread.lines.sublist(thread.lines.length - maxNotificationLines)
      : thread.lines;
  all[thread.key] = NotificationThread(
    roomId: thread.roomId,
    key: thread.key,
    title: thread.title,
    isGroupChat: thread.isGroupChat,
    lines: trimmed,
  ).toJson();
  final gone = [
    for (final key in all.keys)
      if (key != thread.key && !showing.contains(messageNotificationIdFor(key)))
        key,
  ];
  while (all.length > maxNotificationThreads) {
    all.remove(gone.isEmpty ? all.keys.first : gone.removeAt(0));
  }
  await _writeAll(prefs, all);
}

Future<void> clearNotificationThread(
  SharedPreferences prefs,
  String key,
) async {
  final all = _readAll(prefs);
  if (all.remove(key) == null) return;
  await _writeAll(prefs, all);
}

Future<void> clearAllNotificationThreads(SharedPreferences prefs) =>
    prefs.remove(notificationThreadsKey);
