import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/errors/best_effort.dart';
import '../../../../core/matrix/reactions.dart';

const reactionOverflow = 12.0;

const reactionOverflowGap = reactionOverflow + 6;

class ReactionsRow extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const ReactionsRow({super.key, required this.event, required this.timeline});

  Future<void> _toggle(BuildContext context, String key) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await toggleReaction(event, timeline, key);
    } catch (e) {
      logCaught('react', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Reaction not sent. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reactions = reactionSummaries(event, timeline);
    if (reactions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final reaction in reactions)
          Material(
            color: reaction.reactedByMe
                ? colors.secondaryContainer
                : colors.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: reaction.reactedByMe
                    ? colors.primary
                    : colors.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _toggle(context, reaction.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  '${reaction.key} ${reaction.count}',
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: reaction.reactedByMe
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
