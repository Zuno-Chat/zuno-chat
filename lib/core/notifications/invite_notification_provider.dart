import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/notifications/call_notification_service.dart';
import '../calls/serial_lock.dart';
import '../matrix/join_requests.dart';
import '../matrix/matrix_client_provider.dart';
import 'message_notification_poster.dart';
import 'message_notification_provider.dart';
import 'notified_events_store.dart';

MessageNotificationContent? inviteNotificationFor(Client client, Event event) {
  if (event.type != EventTypes.RoomMember) return null;
  if (event.stateKey != client.userID) return null;
  if (event.content['membership'] != 'invite') return null;
  if (event.senderId == client.userID) return null;

  final room = event.room;
  final inviter = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
  final name = inviter.calcDisplayname();
  final body = room.name.isEmpty
      ? 'Invited you to chat'
      : 'Invited you to ${room.name}';
  return MessageNotificationContent(
    roomId: room.id,
    title: name,
    body: body,
    text: body,
    eventId: event.eventId == 'invite_for_${room.id}' ? null : event.eventId,
    isDirectChat: room.isDirectChat,
    senderId: event.senderId,
    senderName: name,
    senderAvatarUrl: inviter.avatarUrl,
    timestamp: event.originServerTs,
  );
}

typedef InviteClaim = ({bool won, DateTime? announcedAt});

final _announcements = SerialLock();

Future<InviteClaim> claimInviteAnnouncement(String roomId) =>
    _announcements.run(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final announcedAt = inviteAnnouncedAt(prefs, roomId);
        if (announcedAt != null) return (won: false, announcedAt: announcedAt);
        await markInviteAnnouncedOnDisk(prefs, roomId);
      } catch (e) {
        debugPrint('zuno/notifications: invite announcement not stored ($e)');
      }
      return (won: true, announcedAt: null);
    });

Future<void> forgetInviteAnnouncements(Iterable<String> roomIds) =>
    _announcements.run(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        await forgetInviteAnnouncementsOnDisk(prefs, roomIds);
      } catch (_) {}
    });

final roomInviteNotificationProvider =
    NotifierProvider<RoomInviteNotificationNotifier, void>(
      RoomInviteNotificationNotifier.new,
    );

class RoomInviteNotificationNotifier extends Notifier<void> {
  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onNotification.stream.listen(
      (event) => _handleEvent(client, event),
    );
    final syncSub = client.onSync.stream.listen(
      (update) => _forgetSettled(client, update),
    );
    ref.onDispose(() {
      sub.cancel();
      syncSub.cancel();
    });
  }

  Future<void> _handleEvent(Client client, Event event) async {
    final content = inviteNotificationFor(client, event);
    if (content == null) return;
    if (ref.read(joinRequestsProvider).contains(content.roomId)) return;
    if (!(await claimInviteAnnouncement(content.roomId)).won) return;
    try {
      await postMessageNotification(
        content,
        client: client,
        includeMessageActions: false,
      );
    } catch (e) {
      await forgetInviteAnnouncements([content.roomId]);
      debugPrint('zuno/notifications: invitation not announced ($e)');
    }
  }

  void _forgetSettled(Client client, SyncUpdate update) {
    final rooms = update.rooms;
    final joined = rooms?.join ?? const <String, JoinedRoomUpdate>{};
    final left = rooms?.leave?.keys ?? const <String>[];
    if (joined.isEmpty && left.isEmpty) return;
    final changed = {
      ...left,
      for (final MapEntry(key: roomId, value: room) in joined.entries)
        if (_carriesOwnMembership(room, client.userID)) roomId,
    };
    unawaited(_forgetIfAnnounced({...joined.keys, ...left}, changed));
  }

  bool _carriesOwnMembership(JoinedRoomUpdate room, String? userId) => [
    ...?room.state,
    ...?room.timeline?.events,
  ].any((e) => e.type == EventTypes.RoomMember && e.stateKey == userId);

  Future<void> _forgetIfAnnounced(
    Set<String> settled,
    Set<String> changed,
  ) async {
    final forget = {...changed, ...await _knownAnnouncements(settled)};
    if (forget.isEmpty) return;
    await forgetInviteAnnouncements(forget);
  }

  Future<Iterable<String>> _knownAnnouncements(Set<String> roomIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return roomIds.where(
        (roomId) => inviteAnnouncedAt(prefs, roomId) != null,
      );
    } catch (_) {
      return const [];
    }
  }
}

Future<void> cancelInviteNotification(Room room) =>
    CallNotificationService.instance.cancelMessageNotification(room.id);
