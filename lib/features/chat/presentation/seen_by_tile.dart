import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/read_receipts.dart';
import '../../../core/matrix/room_changes.dart';
import 'message_actions_sheet.dart';

class SeenByTile extends StatelessWidget {
  final Room room;
  final Event event;

  const SeenByTile({super.key, required this.room, required this.event});

  @override
  Widget build(BuildContext context) => RoomChangesBuilder(
    changes: RoomChanges.any(room),
    builder: (context) {
      final seen = seenByOthers(room, event);
      final l10n = context.l10n;
      final labels = DateLabels.of(context);
      final seenBy = seen
          .map(
            (s) => l10n.chatSeenByEntry(
              s.user.calcDisplayname(),
              labels.dateTime(s.at),
            ),
          )
          .join('\n');
      return MessageFact(
        icon: seen.isEmpty ? Icons.done : Icons.done_all,
        child: Text(
          seen.isEmpty ? l10n.chatNotSeenYet : l10n.chatSeenBy(seenBy),
        ),
      );
    },
  );
}
