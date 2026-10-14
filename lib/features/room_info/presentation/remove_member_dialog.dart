import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';

enum RemoveMemberPlace { room, community }

Future<bool> confirmRemoveMember(
  BuildContext context, {
  required String name,
  required bool ban,
  required RemoveMemberPlace place,
}) async {
  final l10n = context.l10n;
  final consequence = switch ((ban, place)) {
    (true, RemoveMemberPlace.room) => l10n.roomInfoBanRoomBody,
    (true, RemoveMemberPlace.community) => l10n.roomInfoBanCommunityBody,
    (false, RemoveMemberPlace.room) => l10n.roomInfoRemoveRoomBody,
    (false, RemoveMemberPlace.community) => l10n.roomInfoRemoveCommunityBody,
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        ban ? l10n.roomInfoBanTitle(name) : l10n.roomInfoRemoveTitle(name),
      ),
      content: Text(consequence),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(ban ? l10n.roomInfoBan : l10n.roomInfoRemove),
        ),
      ],
    ),
  );
  return confirmed == true;
}
