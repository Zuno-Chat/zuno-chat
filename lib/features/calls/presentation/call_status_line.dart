import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../core/calls/models/call_status.dart';
import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import 'call_status_widgets.dart';

class CallStatusLine extends StatelessWidget {
  final CallStatus status;
  final DateTime? talkingSince;
  final DateTime? encryptingSince;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final CrossAxisAlignment alignment;

  const CallStatusLine({
    super.key,
    required this.status,
    this.talkingSince,
    this.encryptingSince,
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
    final l10n = context.l10n;
    return switch (status) {
      CallStatus.calling => Text(l10n.callsCalling, style: style),
      CallStatus.connecting => Text(l10n.callsConnecting, style: style),
      CallStatus.waiting => Text(
        l10n.callsWaitingForOther,
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
      ),
      CallStatus.talking => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: (style.fontSize ?? 14) + 2,
            color: style.color,
            semanticLabel: l10n.callsEncrypted,
          ),
          const SizedBox(width: 4),
          if (since != null) CallTimer(since: since, style: style),
        ],
      ),
    };
  }
}

class CallTimerSuffix extends StatelessWidget {
  final DateTime since;
  final TextStyle? style;

  const CallTimerSuffix({super.key, required this.since, this.style});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(' · ', style: style),
        CallTimer(since: since, style: style),
      ],
    ),
  );
}

class CallTimer extends StatefulWidget {
  final DateTime since;
  final TextStyle? style;

  const CallTimer({super.key, required this.since, this.style});

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
      formatDuration(clock.now().difference(widget.since)),
      style: widget.style,
    ),
  );
}
