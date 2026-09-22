import 'package:flutter/material.dart';

import '../../../core/ui/line_strut.dart';
import '../../../core/ui/zuno_colors.dart';
import '../data/message_look.dart';

export '../data/message_look.dart' show MetaStatus;

class MessageMeta extends StatelessWidget {
  final String time;
  final bool own;
  final bool edited;
  final MetaStatus status;
  final bool onMedia;

  const MessageMeta({
    super.key,
    required this.time,
    required this.own,
    this.edited = false,
    this.status = MetaStatus.none,
    this.onMedia = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final Color color;
    final Color iconColor;
    final Color readColor;
    if (onMedia) {
      color = Colors.white;
      iconColor = Colors.white70;
      readColor = colors.primaryContainer;
    } else {
      color = own
          ? ZunoColors.ofTheme(theme).onBubbleOutgoingVariant
          : colors.onSurfaceVariant;
      iconColor = color;
      readColor = colors.primary;
    }
    final style = theme.textTheme.labelSmall!.copyWith(color: color);
    final strut = lineStrut(style);
    final icon = switch (status) {
      MetaStatus.none => null,
      MetaStatus.sending => Icons.schedule,
      MetaStatus.sent => Icons.done,
      MetaStatus.read => Icons.done_all,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (edited) ...[
          Text(
            'edited',
            style: style.copyWith(fontStyle: FontStyle.italic),
            strutStyle: strut,
          ),
          const SizedBox(width: 4),
        ],
        Text(time, style: style, strutStyle: strut),
        if (icon != null) ...[
          const SizedBox(width: 3),
          Icon(
            icon,
            size: 15,
            color: status == MetaStatus.read ? readColor : iconColor,
          ),
        ],
      ],
    );
  }
}

class TuckedMeta extends StatelessWidget {
  final Widget meta;
  final Widget Function(InlineSpan spacer) textBuilder;

  const TuckedMeta({super.key, required this.meta, required this.textBuilder});

  @override
  Widget build(BuildContext context) {
    final spacer = WidgetSpan(
      child: ExcludeSemantics(
        child: Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: MediaQuery.withNoTextScaling(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: meta,
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        textBuilder(spacer),
        Positioned(right: 0, bottom: 0, child: meta),
      ],
    );
  }
}
