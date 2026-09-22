import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

bool isNotSent(Event event) =>
    event.status.isError && event.senderId == event.room.client.userID;

List<Event> notSentOwnEvents(Iterable<Event> events) =>
    events.where(isNotSent).toList();

class NotSentRow extends StatelessWidget {
  const NotSentRow({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 14, color: colors.error),
        const SizedBox(width: 4),
        Text(
          'Not sent · Tap to retry',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.error),
        ),
      ],
    );
  }
}
