import 'package:flutter/material.dart';

const collapsedMessageMaxLines = 12;

const collapsedMessageMaxChars = 600;

const collapsedMessageMaxHeight = 260.0;

bool shouldCollapseMessage(String text) {
  if (text.length > collapsedMessageMaxChars) return true;
  return '\n'.allMatches(text).length + 1 > collapsedMessageMaxLines;
}

class ExpandableMessage extends StatefulWidget {
  final String text;
  final Widget Function(BuildContext context, int? maxLines) builder;
  final Widget? collapsedTrailing;

  const ExpandableMessage({
    required this.text,
    required this.builder,
    this.collapsedTrailing,
    super.key,
  });

  @override
  State<ExpandableMessage> createState() => _ExpandableMessageState();
}

class _ExpandableMessageState extends State<ExpandableMessage> {
  bool _expanded = false;

  @override
  void didUpdateWidget(ExpandableMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!shouldCollapseMessage(widget.text) && _expanded) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldCollapseMessage(widget.text)) {
      return widget.builder(context, null);
    }
    final colors = Theme.of(context).colorScheme;
    final trailing = widget.collapsedTrailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.builder(context, _expanded ? null : collapsedMessageMaxLines),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text(
                  _expanded ? 'Show less' : 'Read more',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (!_expanded && trailing != null) ...[
              const SizedBox(width: 16),
              trailing,
            ],
          ],
        ),
      ],
    );
  }
}
