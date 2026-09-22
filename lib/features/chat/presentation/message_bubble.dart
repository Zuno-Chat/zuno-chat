import 'package:flutter/material.dart';

import '../../../core/ui/zuno_colors.dart';
import '../../../core/ui/zuno_theme.dart';
import '../data/message_look.dart';

export '../data/message_look.dart' show RunPosition;

const _runCorner = 6.0;

BorderRadius bubbleRadius({required bool own, required RunPosition position}) {
  const big = Radius.circular(ZunoRadius.large);
  const small = Radius.circular(_runCorner);
  final top = position == RunPosition.single || position == RunPosition.first
      ? big
      : small;
  final bottom = position == RunPosition.single || position == RunPosition.last
      ? big
      : small;
  return BorderRadius.only(
    topLeft: own ? big : top,
    bottomLeft: own ? big : bottom,
    topRight: own ? top : big,
    bottomRight: own ? bottom : big,
  );
}

Color bubbleFill(ThemeData theme, {required bool own}) => own
    ? ZunoColors.ofTheme(theme).bubbleOutgoing
    : theme.colorScheme.surfaceContainerHigh;

Color bubbleInk(ThemeData theme, {required bool own}) => own
    ? ZunoColors.ofTheme(theme).onBubbleOutgoing
    : theme.colorScheme.onSurface;

Color bubbleMuted(ThemeData theme, {required bool own}) => own
    ? ZunoColors.ofTheme(theme).onBubbleOutgoingVariant
    : theme.colorScheme.onSurfaceVariant;

Color quoteFill({required Color surface, required Color bubble}) =>
    Color.alphaBlend(surface.withValues(alpha: 0.5), bubble);

class MessageBubble extends StatelessWidget {
  final bool own;
  final RunPosition position;
  final Widget child;
  final String? senderName;
  final Widget? quote;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.own,
    required this.position,
    required this.child,
    this.senderName,
    this.quote,
    this.padding = const EdgeInsets.fromLTRB(12, 7, 12, 7),
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = bubbleInk(theme, own: own);
    final senderName = this.senderName;
    final quote = this.quote;

    Widget column = Column(
      crossAxisAlignment: quote == null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (senderName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
            child: Text(
              senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (quote != null)
          Padding(
            padding: EdgeInsets.fromLTRB(8, senderName == null ? 8 : 3, 8, 0),
            child: quote,
          ),
        Padding(padding: padding, child: child),
      ],
    );
    if (quote != null) column = IntrinsicWidth(child: column);

    return Material(
      color: bubbleFill(theme, own: own),
      borderRadius: bubbleRadius(own: own, position: position),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodyLarge!.copyWith(
            color: ink,
            height: 1.3,
            letterSpacing: 0.2,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: ink),
            child: column,
          ),
        ),
      ),
    );
  }
}
