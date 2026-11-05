import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/notifications/messages/message_notification_content.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';

class FakeNotificationRenderer implements NotificationRenderer {
  final _contents = <String, MessageNotificationContent>{};
  final _titles = <String, String>{};
  int rebuilt = 0;

  MessageNotificationContent remembered(MessageNotificationContent content) {
    _titles[content.roomId] = content.title;
    if (content.eventId case final eventId?) _contents[eventId] = content;
    return content;
  }

  @override
  Future<String> title(String roomId) async => _title(roomId);

  String _title(String roomId) =>
      _titles[roomId] ?? englishLocalizations.notificationsNewMessage;

  @override
  Uri? avatarOf(String roomId, String senderId) => _contents.values
      .where((c) => c.roomId == roomId && c.senderId == senderId)
      .map((c) => c.senderAvatarUrl)
      .nonNulls
      .lastOrNull;

  @override
  Future<NotificationLine> line(
    String roomId,
    StoredNotificationLine stored,
  ) async {
    rebuilt++;
    final content = _contents[stored.eventId];
    return stored.rendered(
      senderName: content?.senderName ?? content?.title ?? _title(roomId),
      senderAvatarUrl: content?.senderAvatarUrl,
      text: stored.placeholder || content == null
          ? englishLocalizations.notificationsNewMessage
          : content.text,
    );
  }
}
