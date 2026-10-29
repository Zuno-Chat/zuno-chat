import 'package:flutter/material.dart';

import 'line_strut.dart';
import 'zuno_theme.dart';

class TimelinePill extends StatelessWidget {
  final String text;

  const TimelinePill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(ZunoRadius.compact),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
        strutStyle: lineStrut(style),
      ),
    );
  }
}
