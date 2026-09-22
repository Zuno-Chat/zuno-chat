import 'package:flutter/material.dart';

class StepLayout extends StatelessWidget {
  final Widget hero;
  final String title;
  final String? body;
  final List<Widget> children;
  final List<Widget> actions;
  final bool actionsFollowContent;
  final EdgeInsets padding;

  const StepLayout({
    super.key,
    required this.hero,
    required this.title,
    this.body,
    this.children = const [],
    this.actions = const [],
    this.actionsFollowContent = false,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 16),
  });

  static const _minimumScrollArea = 120.0;

  List<Widget> _content(ThemeData theme) {
    final body = this.body;
    return [
      const SizedBox(height: 16),
      Center(child: hero),
      const SizedBox(height: 28),
      Text(
        title,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall,
      ),
      if (body != null) ...[
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (children.isNotEmpty) ...[const SizedBox(height: 24), ...children],
      const SizedBox(height: 16),
    ];
  }

  Widget _scrollingColumn(double minHeight, List<Widget> children) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionHeight = 28 + MediaQuery.textScalerOf(context).scale(20);
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pinned =
              constraints.maxHeight - actions.length * actionHeight >=
              _minimumScrollArea;
          if (!pinned) {
            return _scrollingColumn(constraints.maxHeight, [
              ..._content(theme),
              ...actions,
            ]);
          }
          if (actionsFollowContent) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: _scrollingColumn(0, _content(theme))),
                ...actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) =>
                      _scrollingColumn(area.maxHeight, _content(theme)),
                ),
              ),
              ...actions,
            ],
          );
        },
      ),
    );
  }
}
