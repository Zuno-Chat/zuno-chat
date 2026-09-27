import 'package:flutter/material.dart';

import '../../../core/matrix/linkified_text.dart';

const _foldedTopicLines = 3;

class RoomTopic extends StatefulWidget {
  final String topic;

  const RoomTopic({required this.topic, super.key});

  @override
  State<RoomTopic> createState() => _RoomTopicState();
}

class _RoomTopicState extends State<RoomTopic> {
  bool _expanded = false;

  bool _overflows(TextStyle style, double maxWidth) {
    var measured = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      measured = measured.copyWith(fontWeight: FontWeight.bold);
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.topic, style: measured),
      maxLines: _foldedTopicLines,
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final foldable = _overflows(style, constraints.maxWidth);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinkifiedText(
              widget.topic,
              style: style,
              maxLines: foldable && !_expanded ? _foldedTopicLines : null,
              textAlign: TextAlign.center,
            ),
            if (foldable)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Read more'),
              ),
          ],
        );
      },
    );
  }
}
