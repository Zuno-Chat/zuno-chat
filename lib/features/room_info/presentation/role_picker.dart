import 'package:flutter/material.dart';

import '../../../core/matrix/room_roles.dart';

Future<RoomRole?> showRolePicker(
  BuildContext context, {
  required RoomRole current,
  required List<RoomRole> options,
}) {
  final sortedOptions = [...options]
    ..sort((a, b) => b.powerLevel.compareTo(a.powerLevel));

  return showModalBottomSheet<RoomRole>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          for (final role in sortedOptions)
            ListTile(
              leading: role == current
                  ? const Icon(Icons.check_outlined)
                  : const SizedBox(width: 24),
              title: Text(role.label),
              onTap: () => Navigator.of(context).pop(role),
            ),
        ],
      ),
    ),
  );
}
