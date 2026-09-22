import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
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
    try {
      await setRoomPermissionLevel(widget.room, permission, chosen.powerLevel);
      if (mounted) setState(() {});
    } catch (e) {
      logCaught('update permissions', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Not saved. Try again.')),
      );
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

    Widget roleLabel(RoomPermission permission) => Text(
      roomRoleForLevel(permission.read(content)).label,
      style: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    Widget section(String title, RoomPermissionSection kind) => CardGroup(
      title: title,
      children: [
        for (final permission in roomPermissions.where(
          (p) => p.section == kind,
        ))
          ListTile(
            title: Text(permission.label),
            trailing: roleLabel(permission),
            onTap: editable ? () => _edit(permission) : null,
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Roles & permissions')),
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
                      const Expanded(
                        child: Text(
                          'Only admins can change these. You can view them '
                          'here.',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _bannerDismissed = true),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          CardGroup(
            title: 'Room defaults',
            children: [
              ListTile(
                title: const Text('Default role for new members'),
                subtitle: const Text(
                  'The role everyone starts with when they join.',
                ),
                trailing: roleLabel(roomDefaultRoleSetting),
                onTap: editable ? () => _edit(roomDefaultRoleSetting) : null,
              ),
            ],
          ),
          section('Basic', RoomPermissionSection.basic),
          section('Advanced', RoomPermissionSection.advanced),
        ],
      ),
    );
  }
}
