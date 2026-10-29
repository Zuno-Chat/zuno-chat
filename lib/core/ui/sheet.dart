import 'package:flutter/material.dart';

import '../l10n/display_text.dart';
import 'keep_clear.dart';

class SheetAction<T> {
  final T value;
  final IconData icon;
  final String label;
  final bool destructive;

  const SheetAction(
    this.value, {
    required this.icon,
    @displayText required this.label,
    this.destructive = false,
  });
}

Future<T?> showActionSheet<T>(
  BuildContext context, {
  @displayText String? title,
  required List<SheetAction<T>> actions,
}) => showSheet<T>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            ListTile(
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
          for (final action in actions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              iconColor: action.destructive ? danger : null,
              textColor: action.destructive ? danger : null,
              onTap: () => Navigator.of(context).pop(action.value),
            ),
        ],
      ),
    );
  },
);

class SheetChoice<T> {
  final T value;
  final String label;
  final String? subtitle;

  const SheetChoice(
    this.value, {
    @displayText required this.label,
    @displayText this.subtitle,
  });
}

Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required T? current,
  required List<SheetChoice<T>> choices,
  @displayText String? header,
}) => showSheet<T>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                header,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final choice in choices)
            ListTile(
              leading: choice.value == current
                  ? const Icon(Icons.check_outlined)
                  : const SizedBox(width: 24),
              title: Text(choice.label),
              subtitle: switch (choice.subtitle) {
                final subtitle? => Text(subtitle),
                null => null,
              },
              onTap: () => Navigator.of(context).pop(choice.value),
            ),
        ],
      ),
    );
  },
);

Future<T?> showSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  showDragHandle: showDragHandle,
  builder: (context) => KeepClearArea.surface(
    child: isScrollControlled
        ? builder(context)
        : SingleChildScrollView(child: builder(context)),
  ),
);

class SheetTitle extends StatelessWidget {
  final String text;

  const SheetTitle(@displayText this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
