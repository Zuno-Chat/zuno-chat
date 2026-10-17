import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';

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
          context.l10n.chatNotSentRetry,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.error),
        ),
      ],
    );
  }
}
