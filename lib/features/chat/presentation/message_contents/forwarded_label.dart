import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../forward_icon.dart';
import '../message_bubble.dart';

class ForwardedLabel extends StatelessWidget {
  final bool own;

  const ForwardedLabel({required this.own, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = bubbleMuted(theme, own: own);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ForwardIcon(size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          context.l10n.chatForwarded,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
