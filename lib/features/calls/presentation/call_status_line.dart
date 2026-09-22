import 'dart:async';

import 'package:flutter/material.dart';

import 'call_status_widgets.dart';

enum CallStatus { calling, connecting, waiting, encrypting, talking }

String callClock(Duration elapsed) {
  final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = seconds ~/ 3600;
  final clock = '${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}';
  return hours == 0 ? clock : '$hours:$clock';
}

class CallStatusLine extends StatelessWidget {
  final CallStatus status;
  final DateTime? talkingSince;
  final DateTime? encryptingSince;
  final DateTime Function() now;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final CrossAxisAlignment alignment;

  const CallStatusLine({
    super.key,
    required this.status,
    this.talkingSince,
    this.encryptingSince,
    this.now = DateTime.now,
    this.style,
    this.hintStyle,
    this.alignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        this.style ??
        theme.textTheme.bodyLarge!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    final since = talkingSince;
    return switch (status) {
      CallStatus.calling => Text('Calling…', style: style),
      CallStatus.connecting => Text('Connecting…', style: style),
      CallStatus.waiting => Text(
        'Waiting for the other side to join…',
        style: style,
        textAlign: alignment == CrossAxisAlignment.center
            ? TextAlign.center
            : TextAlign.start,
      ),
      CallStatus.encrypting => EncryptingLabel(
        style: style,
        hintStyle:
            hintStyle ??
            theme.textTheme.bodyMedium!.copyWith(color: style.color),
        alignment: alignment,
        hintMaxLines: null,
        since: encryptingSince,
        now: now,
      ),
      CallStatus.talking => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: (style.fontSize ?? 14) + 2,
            color: style.color,
            semanticLabel: 'Encrypted',
          ),
          const SizedBox(width: 4),
          if (since != null) CallTimer(since: since, now: now, style: style),
        ],
      ),
    };
  }
}

class CallTimerSuffix extends StatelessWidget {
  final DateTime since;
  final DateTime Function() now;
  final TextStyle? style;

  const CallTimerSuffix({
    super.key,
    required this.since,
    this.now = DateTime.now,
    this.style,
  });

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(' · ', style: style),
        CallTimer(since: since, now: now, style: style),
      ],
    ),
  );
}

class CallTimer extends StatefulWidget {
  final DateTime since;
  final DateTime Function() now;
  final TextStyle? style;

  const CallTimer({
    super.key,
    required this.since,
    this.now = DateTime.now,
    this.style,
  });

  @override
  State<CallTimer> createState() => _CallTimerState();
}

class _CallTimerState extends State<CallTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Text(
      callClock(widget.now().difference(widget.since)),
      style: widget.style,
    ),
  );
}
