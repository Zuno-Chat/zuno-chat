import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/ui/confirm_dialog.dart';

enum RemoveMemberPlace { room, community, call }

Future<bool> confirmRemoveMember(
  BuildContext context, {
  required String name,
  bool ban = false,
  required RemoveMemberPlace place,
}) {
  assert(
    !ban || place != RemoveMemberPlace.call,
    'Nobody is banned from a call',
  );
  final l10n = context.l10n;
  final (title, consequence) = switch ((ban, place)) {
    (true, RemoveMemberPlace.room) => (
      l10n.roomInfoBanTitle(name),
      l10n.roomInfoBanRoomBody,
    ),
    (true, RemoveMemberPlace.community) => (
      l10n.roomInfoBanTitle(name),
      l10n.roomInfoBanCommunityBody,
    ),
    (false, RemoveMemberPlace.room) => (
      l10n.roomInfoRemoveTitle(name),
      l10n.roomInfoRemoveRoomBody,
    ),
    (false, RemoveMemberPlace.community) => (
      l10n.roomInfoRemoveTitle(name),
      l10n.roomInfoRemoveCommunityBody,
    ),
    (_, RemoveMemberPlace.call) => (
      l10n.callsRemoveFromCallTitle(name),
      l10n.callsRemoveFromCallBody,
    ),
  };
  return confirm(
    context,
    title: title,
    body: consequence,
    confirmLabel: ban ? l10n.roomInfoBan : l10n.roomInfoRemove,
    tone: ConfirmTone.destructive,
  );
}
