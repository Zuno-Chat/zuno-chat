import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/bearer_authorization.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_timeline_reload.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/shortcuts/home_screen_shortcut.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';

List<PopupMenuEntry<void>> roomMenuItems(
  BuildContext context,
  WidgetRef ref,
  Room room, {
  required VoidCallback onOpenInfo,
  required VoidCallback onReload,
}) {
  final l10n = context.l10n;
  return [
    PopupMenuItem(
      onTap: onOpenInfo,
      child: Text(room.isDirectChat ? l10n.chatChatInfo : l10n.chatRoomInfo),
    ),
    if (!room.isDirectChat && room.canInvite)
      PopupMenuItem(
        onTap: () => unawaited(
          inviteFromDialog(context, room, title: l10n.chatAddMembers),
        ),
        child: Text(l10n.chatAddMembers),
      ),
    if (ref.read(platformCapabilitiesProvider).homeScreenShortcuts)
      PopupMenuItem(
        onTap: () => unawaited(_addToHomeScreen(context, room)),
        child: Text(l10n.chatAddToHomeScreen),
      ),
    if (canReloadRoomTimeline(room))
      PopupMenuItem(
        onTap: () => unawaited(_confirmReload(context, onReload)),
        child: Text(l10n.chatReloadMessages),
      ),
    PopupMenuItem(
      onTap: () => unawaited(_exit(context, ref, room)),
      child: Text(roomExitLabel(room, l10n)),
    ),
  ];
}

Future<void> _addToHomeScreen(BuildContext context, Room room) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final iconBytes = await _roomAvatarBytes(room);
  try {
    final requested = await pinRoomShortcut(
      roomId: room.id,
      label: roomTitle(room, l10n),
      iconBytes: iconBytes,
    );
    messenger.say(
      requested ? l10n.chatShortcutRequested : l10n.chatShortcutUnsupported,
    );
  } catch (e, s) {
    reportCaught('add shortcut', e, s);
    messenger.sayFailed(l10n, e, failed: l10n.chatShortcutFailed);
  }
}

Future<Uint8List?> _roomAvatarBytes(Room room) async {
  final avatarUrl = room.avatar;
  if (avatarUrl == null) return null;
  try {
    final client = room.client;
    final uri = await avatarUrl.getThumbnailUri(
      client,
      width: 192,
      height: 192,
    );
    final response = await client.httpClient.get(
      uri,
      headers: {'authorization': await bearerAuthorization(client)},
    );
    return response.statusCode == 200 ? response.bodyBytes : null;
  } catch (e, s) {
    reportCaught('fetch shortcut icon', e, s);
    return null;
  }
}

Future<void> _confirmReload(BuildContext context, VoidCallback reload) async {
  final l10n = context.l10n;
  final confirmed = await confirm(
    context,
    title: l10n.chatReloadTitle,
    body: l10n.chatReloadBody,
    confirmLabel: l10n.chatReload,
  );
  if (confirmed && context.mounted) reload();
}

Future<void> _exit(BuildContext context, WidgetRef ref, Room room) async {
  final left = await confirmAndExitRoom(
    context,
    room,
    endCallsIn: ref.read(endCallsInProvider),
  );
  if (left && context.mounted) Navigator.of(context).pop();
}
