import 'package:flutter/material.dart';

import '../../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../data/message_kinds.dart';
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
    final IconData icon;
    if (missed) {
      icon = Icons.call_missed;
    } else if (summary.kind == 'video') {
      icon = Icons.videocam_outlined;
    } else {
      icon = Icons.call_outlined;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Icon(icon, size: 18, color: missed ? colors.error : null),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            ended ? summary.label : summary.displayBody,
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
