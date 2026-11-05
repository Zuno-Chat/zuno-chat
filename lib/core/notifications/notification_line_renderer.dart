import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';
import '../matrix/encryption/decrypt_again.dart';
import '../matrix/events/event_display.dart';
import '../matrix/rooms/room_title.dart';
import 'join_request_notification_provider.dart';
import 'messages/message_notification_content.dart';
import 'messages/notification_thread.dart';
import 'room_invite_notification_provider.dart';
import 'verification_request_notification.dart';

class ClientNotificationRenderer implements NotificationRenderer {
  const ClientNotificationRenderer(this._client);

  final Client _client;

  @override
  Future<String> title(String roomId) async {
    final l10n = deviceLocalizations();
    final room = _client.getRoomById(roomId);
    if (room == null) return l10n.notificationsNewMessage;
    await loadRoomNameMembers(room);
    return roomTitle(room, l10n);
  }

  @override
  Uri? avatarOf(String roomId, String senderId) => _client
      .getRoomById(roomId)
      ?.unsafeGetUserFromMemoryOrFallback(senderId)
      .avatarUrl;

  @override
  Future<NotificationLine> line(
    String roomId,
    StoredNotificationLine stored,
  ) async {
    final l10n = deviceLocalizations();
    final room = _client.getRoomById(roomId);
    if (room != null && !stored.placeholder) {
      try {
        if (await _rebuilt(room, stored, l10n) case final line?) return line;
      } catch (e, s) {
        reportCaught('rebuild a notification line', e, s);
      }
    }
    return stored.untold(await title(roomId), l10n);
  }

  Future<NotificationLine?> _rebuilt(
    Room room,
    StoredNotificationLine stored,
    AppLocalizations l10n,
  ) async {
    final (sender, event) = await (
      _sender(room, stored.senderId),
      _event(room, stored.eventId),
    ).wait;
    if (stored.kind == NotificationLineKind.notice) {
      final notice = stored.eventId == null
          ? _invite(room, stored)
          : _notice(event);
      return notice == null
          ? null
          : stored.rendered(
              senderName: notice.senderName ?? notice.title,
              senderAvatarUrl: notice.senderAvatarUrl,
              text: notice.text,
            );
    }
    return stored.rendered(
      senderName: sender?.calcDisplayname() ?? await title(room.id),
      senderAvatarUrl: sender?.avatarUrl,
      text: event == null
          ? l10n.notificationsNewMessage
          : summarize(l10n, event).text,
    );
  }

  MessageNotificationContent? _notice(Event? event) => event == null
      ? null
      : inviteNotificationFor(_client, event) ??
            joinRequestNotificationFor(_client, event) ??
            verificationRequestNotificationFor(_client, event);

  MessageNotificationContent? _invite(
    Room room,
    StoredNotificationLine stored,
  ) {
    final userId = _client.userID;
    final member = userId == null
        ? null
        : room.getState(EventTypes.RoomMember, userId);
    return member == null
        ? null
        : inviteNotificationOf(
            _client,
            room,
            member,
            timestamp: stored.timestamp,
          );
  }

  Future<Event?> _event(Room room, String? eventId) async {
    if (eventId == null) return null;
    final saved = await _client.database.getEventById(eventId, room);
    if (saved == null || saved.type != EventTypes.Encrypted) return saved;
    return decryptAgain(_client, saved);
  }

  Future<User?> _sender(Room room, String senderId) async {
    if (!senderId.startsWith('@')) return null;
    await loadRoomMember(room, senderId);
    return room.unsafeGetUserFromMemoryOrFallback(senderId);
  }
}
