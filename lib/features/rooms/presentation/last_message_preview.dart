import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/late_decryptions.dart';
import '../../../core/matrix/message_icons.dart';
import '../../../core/matrix/undecryptable_event.dart';
import '../../../core/ui/line_strut.dart';
import '../../chat/presentation/undecryptable_message.dart';

class LastMessagePreview extends StatefulWidget {
  final Room room;
  final Event? event;
  final MessageSummary? summary;

  const LastMessagePreview({
    required this.room,
    required this.event,
    required this.summary,
    super.key,
  });

  @override
  State<LastMessagePreview> createState() => _LastMessagePreviewState();
}

class _LastMessagePreviewState extends State<LastMessagePreview> {
  Event? _opened;
  StreamSubscription<Event>? _openings;

  @override
  void initState() {
    super.initState();
    _openLocked();
  }

  @override
  void didUpdateWidget(covariant LastMessagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.event, widget.event)) return;
    _opened = null;
    _openLocked();
  }

  @override
  void dispose() {
    unawaited(_openings?.cancel());
    super.dispose();
  }

  void _openLocked() {
    unawaited(_openings?.cancel());
    _openings = null;
    final event = widget.event;
    if (event == null || !isUndecryptableEvent(event)) return;
    final late = LateDecryptions.of(widget.room.client);
    _openings = late.decrypted
        .where((opened) => opened.eventId == event.eventId)
        .listen((opened) => setState(() => _opened = opened));
    unawaited(late.tryOpen(event));
  }

  @override
  Widget build(BuildContext context) {
    final strut = inheritedLineStrut(context);
    if (widget.event == null) {
      return Text(context.l10n.roomsNoMessages, strutStyle: strut);
    }
    final opened = _opened;
    final summary = opened != null && isPreviewableLastEvent(opened)
        ? summarize(context.l10n, opened)
        : widget.summary;
    if (summary == null) return Text('', strutStyle: strut);
    return switch (summary.kind) {
      MessageKind.deleted => Text(
        summary.text,
        strutStyle: strut,
        style: const TextStyle(fontStyle: FontStyle.italic),
      ),
      MessageKind.undecryptable => const UndecryptablePreviewText(),
      MessageKind.nonMessage ||
      MessageKind.hiddenSignaling => const SizedBox.shrink(),
      MessageKind.text ||
      MessageKind.photo ||
      MessageKind.video ||
      MessageKind.voice ||
      MessageKind.file ||
      MessageKind.location ||
      MessageKind.liveLocation ||
      MessageKind.callSummary => _SummaryLine(
        icon: messageIcon(summary),
        text: summary.text,
        color: summary.call?.status == CallSummaryStatus.missed
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    };
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color? color;

  const _SummaryLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final line = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      strutStyle: inheritedLineStrut(context),
      style: color == null ? null : TextStyle(color: color),
    );
    final icon = this.icon;
    if (icon == null) return line;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(child: line),
      ],
    );
  }
}
