import 'package:flutter/material.dart';

import '../../../core/ui/line_strut.dart';

class DateDivider extends StatelessWidget {
  final String label;

  const DateDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: style, strutStyle: lineStrut(style)),
        ),
      ),
    );
  }
}
