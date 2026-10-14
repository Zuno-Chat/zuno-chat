import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'role_picker.dart';

class RoomPermissionsPage extends StatefulWidget {
  final Room room;

  const RoomPermissionsPage({required this.room, super.key});

  @override
  State<RoomPermissionsPage> createState() => _RoomPermissionsPageState();
}

class _RoomPermissionsPageState extends State<RoomPermissionsPage> {
  bool _bannerDismissed = false;

  Future<void> _edit(RoomPermission permission) async {
    final content =
        widget.room.getState(EventTypes.RoomPowerLevels)?.content ?? const {};
    final current = roomRoleForLevel(permission.read(content));
    final chosen = await showRolePicker(
      context,
      current: current,
      options: RoomRole.values,
    );
    if (chosen == null || chosen == current || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await setRoomPermissionLevel(widget.room, permission, chosen.powerLevel);
      if (mounted) setState(() {});
    } catch (e, s) {
      reportCaught('update permissions', e, s);
      messenger.showSnackBar(SnackBar(content: Text(l10n.roomInfoNotSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final access = roomPermissionsAccessFor(room);
    final editable = access == RoomPermissionsAccess.edit;
    final content =
        room.getState(EventTypes.RoomPowerLevels)?.content ?? const {};
    final theme = Theme.of(context);
    final l10n = context.l10n;

    Widget roleLabel(RoomPermission permission) => Text(
      roomRoleForLevel(permission.read(content)).label(l10n),
      style: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    Widget section(PermissionGroup group) => CardGroup(
      title: group.title(l10n),
      children: [
        for (final permission in group.permissions)
          ListTile(
            title: Text(permission.label(l10n)),
            trailing: roleLabel(permission),
            onTap: editable ? () => _edit(permission) : null,
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.roomInfoRolesTitle)),
      body: CardListView(
        children: [
          if (access == RoomPermissionsAccess.readOnly && !_bannerDismissed)
            CardGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(l10n.roomInfoAdminsOnlyBanner)),
                      TextButton(
                        onPressed: () =>
                            setState(() => _bannerDismissed = true),
                        child: Text(l10n.commonDismiss),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          CardGroup(
            title: room.isSpace
                ? l10n.roomInfoCommunityDefaults
                : l10n.roomInfoRoomDefaults,
            children: [
              ListTile(
                title: Text(l10n.matrixPermissionUsersDefault),
                subtitle: Text(l10n.roomInfoDefaultRoleHint),
                trailing: roleLabel(roomDefaultRoleSetting),
                onTap: editable ? () => _edit(roomDefaultRoleSetting) : null,
              ),
            ],
          ),
          for (final group
              in room.isSpace
                  ? communityPermissionGroups
                  : roomPermissionGroups)
            section(group),
        ],
      ),
    );
  }
}
