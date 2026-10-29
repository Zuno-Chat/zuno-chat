import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/ui/sheet.dart';

Future<RoomRole?> showRolePicker(
  BuildContext context, {
  required RoomRole current,
  required List<RoomRole> options,
}) => showChoiceSheet(
  context,
  current: current,
  choices: [
    for (final role in [
      ...options,
    ]..sort((a, b) => b.powerLevel.compareTo(a.powerLevel)))
      SheetChoice(role, label: role.label(context.l10n)),
  ],
);
