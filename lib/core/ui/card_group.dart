import 'package:flutter/material.dart';

import 'zuno_theme.dart';

TextStyle cardGroupTitleStyle(BuildContext context) {
  final titleSmall = Theme.of(context).textTheme.titleSmall!;
  return titleSmall.copyWith(fontWeight: FontWeight.w500);
}

class CardGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const CardGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ZunoRadius.large),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                child: Text(title, style: cardGroupTitleStyle(context)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}
