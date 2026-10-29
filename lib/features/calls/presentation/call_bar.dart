import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/models/call_status.dart';
import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/zuno_colors.dart';
import 'call_status_line.dart';

String? callBarLabel(
  AppLocalizations l10n,
  CallStatus status, {
  required bool reconnecting,
}) {
  if (reconnecting) return l10n.callsReconnecting;
  return switch (status) {
    CallStatus.calling => l10n.callsCalling,
    CallStatus.connecting => l10n.callsConnecting,
    CallStatus.waiting => l10n.callsWaiting,
    CallStatus.encrypting => l10n.callsEncrypting,
    CallStatus.talking => null,
  };
}

class CallBar extends StatelessWidget {
  final ActiveCallController call;
  final VoidCallback onTap;

  const CallBar({required this.call, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: onCallActionColor);
    final l10n = context.l10n;
    final label = callBarLabel(
      l10n,
      call.status,
      reconnecting: call.reconnecting,
    );
    final title = roomTitle(call.session.room, l10n);
    final muted = call.local?.audioMuted ?? false;
    return Semantics(
      container: true,
      button: true,
      label: l10n.callsReturnToCall,
      value: [title, ?label, if (muted) l10n.callsMuted].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          color: callAcceptColor,
          child: InkWell(
            onTap: onTap,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      const Icon(
                        Icons.call,
                        size: 18,
                        color: onCallActionColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CallTitleStatus(
                          call: call,
                          title: title,
                          style: style,
                        ),
                      ),
                      if (muted) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.mic_off_outlined,
                          size: 18,
                          color: onCallActionColor,
                        ),
                      ],
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.4,
                        ),
                        child: Text(
                          l10n.callsReturnToCall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CallTitleStatus extends StatelessWidget {
  final ActiveCallController call;
  final String title;
  final TextStyle style;
  final MainAxisAlignment alignment;

  const CallTitleStatus({
    required this.call,
    required this.title,
    required this.style,
    this.alignment = MainAxisAlignment.start,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final label = callBarLabel(
      context.l10n,
      call.status,
      reconnecting: call.reconnecting,
    );
    final since = call.talkingSince;
    return Row(
      mainAxisAlignment: alignment,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (label != null)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(detailSeparator, style: style),
                  Text(label, style: style),
                ],
              ),
            ),
          )
        else if (since != null)
          Flexible(
            child: CallTimerSuffix(since: since, style: style),
          ),
      ],
    );
  }
}
