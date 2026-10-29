import 'package:flutter/material.dart';

import '../../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../../core/format/human_units.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/message_icons.dart';
import '../message_bubble.dart';

class CallSummaryTile extends StatelessWidget {
  final CallSummary summary;
  final bool own;
  final Widget meta;

  const CallSummaryTile({
    super.key,
    required this.summary,
    required this.own,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final missed = summary.status == CallSummaryStatus.missed;
    final ended = summary.status == CallSummaryStatus.ended;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Icon(
            callSummaryIcon(summary),
            size: 18,
            color: missed ? colors.error : null,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            ended
                ? summary.localizedLabel(context.l10n)
                : summary.localizedBody(context.l10n),
            overflow: TextOverflow.ellipsis,
            style: missed ? TextStyle(color: colors.error) : null,
          ),
        ),
        if (ended) ...[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              formatDuration(Duration(milliseconds: summary.durationMs)),
              style: theme.textTheme.labelMedium!.copyWith(
                color: bubbleMuted(theme, own: own),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Padding(padding: const EdgeInsets.only(bottom: 2), child: meta),
      ],
    );
  }
}
