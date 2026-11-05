import 'dart:math';

import '../../brand.dart';
import '../../l10n/l10n.dart';
import '../settings/notification_preview.dart';

const maxNotificationLines = 8;

enum NotificationLineKind {
  message,
  callSummary,
  notice;

  String textAt(
    NotificationPreview preview,
    String text,
    AppLocalizations l10n,
  ) => switch (preview) {
    NotificationPreview.full => text,
    NotificationPreview.nameOnly =>
      this == message ? l10n.notificationsNewMessage : text,
    NotificationPreview.nothing => l10n.notificationsNewMessage,
  };
}

abstract interface class NotificationRenderer {
  Future<NotificationLine> line(String roomId, StoredNotificationLine stored);

  Future<String> title(String roomId);

  Uri? avatarOf(String roomId, String senderId);
}

class StoredNotificationLine {
  final String? eventId;
  final String senderId;
  final NotificationLineKind kind;
  final DateTime timestamp;
  final bool placeholder;
  final String? imageUri;
  final String? imageMimeType;
  final bool quiet;

  const StoredNotificationLine({
    required this.eventId,
    required this.senderId,
    this.kind = NotificationLineKind.message,
    required this.timestamp,
    this.placeholder = false,
    this.imageUri,
    this.imageMimeType,
    this.quiet = false,
  });

  NotificationLine rendered({
    required String senderName,
    Uri? senderAvatarUrl,
    required String text,
  }) => NotificationLine(
    this,
    senderName: senderName,
    senderAvatarUrl: senderAvatarUrl,
    text: text,
  );

  NotificationLine untold(String senderName, AppLocalizations l10n) =>
      rendered(senderName: senderName, text: l10n.notificationsNewMessage);

  StoredNotificationLine _withoutImage() => StoredNotificationLine(
    eventId: eventId,
    senderId: senderId,
    kind: kind,
    timestamp: timestamp,
    placeholder: placeholder,
    quiet: quiet,
  );

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'senderId': senderId,
    'kind': kind.name,
    'ts': timestamp.toUtc().millisecondsSinceEpoch,
    'placeholder': placeholder,
    'imageUri': imageUri,
    'imageMimeType': imageMimeType,
    'quiet': quiet,
  };

  static StoredNotificationLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final senderId = json['senderId'];
    final ts = json['ts'];
    if (senderId is! String || ts is! int) return null;
    return StoredNotificationLine(
      eventId: json['eventId'] as String?,
      senderId: senderId,
      kind: NotificationLineKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => NotificationLineKind.message,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
      placeholder: json['placeholder'] == true,
      imageUri: json['imageUri'] as String?,
      imageMimeType: json['imageMimeType'] as String?,
      quiet: json['quiet'] == true,
    );
  }
}

class StoredNotificationThread {
  final String key;
  final String roomId;
  final bool isGroupChat;
  final NotificationPreview? preview;
  final List<StoredNotificationLine> lines;

  const StoredNotificationThread({
    required this.roomId,
    String? key,
    required this.isGroupChat,
    this.preview,
    required this.lines,
  }) : key = key ?? roomId;

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'isGroupChat': isGroupChat,
    'preview': preview?.wire,
    'lines': [
      for (final line in lines.skip(
        max(0, lines.length - maxNotificationLines),
      ))
        line.toJson(),
    ],
  };

  static StoredNotificationThread? fromJson(String key, Object? json) {
    if (json is! Map) return null;
    final rawLines = json['lines'];
    final roomId = json['roomId'];
    return StoredNotificationThread(
      key: key,
      roomId: roomId is String ? roomId : key,
      isGroupChat: json['isGroupChat'] == true,
      preview: NotificationPreview.values
          .where((level) => level.wire == json['preview'])
          .firstOrNull,
      lines: rawLines is List
          ? rawLines.map(StoredNotificationLine.fromJson).nonNulls.toList()
          : const [],
    );
  }
}

class NotificationLine {
  final StoredNotificationLine stored;
  final String senderName;
  final Uri? senderAvatarUrl;
  final String text;

  const NotificationLine(
    this.stored, {
    required this.senderName,
    this.senderAvatarUrl,
    required this.text,
  });

  NotificationLine _shownAt(
    NotificationPreview preview,
    AppLocalizations l10n,
  ) => NotificationLine(
    preview.showsImages ? stored : stored._withoutImage(),
    senderName: preview.showsSenders ? senderName : zunoName,
    senderAvatarUrl: preview.showsSenders ? senderAvatarUrl : null,
    text: stored.kind.textAt(preview, text, l10n),
  );
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

  StoredNotificationThread storedAt(NotificationPreview preview) =>
      StoredNotificationThread(
        roomId: roomId,
        key: key,
        isGroupChat: isGroupChat,
        preview: preview,
        lines: [for (final line in lines) line.stored],
      );

  NotificationThread shownAt(
    NotificationPreview preview,
    AppLocalizations l10n,
  ) => NotificationThread(
    roomId: roomId,
    key: key,
    title: preview.showsSenders ? title : zunoName,
    isGroupChat: isGroupChat,
    lines: [for (final line in lines) line._shownAt(preview, l10n)],
  );

  String bodyAt(NotificationPreview preview, AppLocalizations l10n) {
    final line = lines.last._shownAt(preview, l10n);
    if (!preview.showsSenders) return line.text;
    if (line.stored.placeholder) return l10n.notificationsTapToOpen;
    return isGroupChat && line.stored.kind != NotificationLineKind.notice
        ? l10n.notificationsSenderText(line.senderName, line.text)
        : line.text;
  }
}
