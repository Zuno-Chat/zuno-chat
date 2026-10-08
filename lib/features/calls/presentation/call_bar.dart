import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/models/call_status.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/zuno_colors.dart';
import 'call_status_line.dart';
import 'call_status_widgets.dart';

const returnToCallLabel = 'Return to call';

String? callBarLabel(CallStatus status, {required bool reconnecting}) {
  if (reconnecting) return 'Reconnecting…';
  return switch (status) {
    CallStatus.calling => 'Calling…',
    CallStatus.connecting => 'Connecting…',
    CallStatus.waiting => 'Waiting…',
    CallStatus.encrypting => EncryptingLabel.label,
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
    final since = call.talkingSince;
    final label = callBarLabel(call.status, reconnecting: call.reconnecting);
    final title = roomTitle(call.session.room);
    final muted = call.local?.audioMuted ?? false;
    return Semantics(
      container: true,
      button: true,
      label: returnToCallLabel,
      value: [title, ?label, if (muted) 'Muted'].join(', '),
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
                        child: Row(
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
                                      Text(' · ', style: style),
                                      Text(label, style: style),
                                    ],
                                  ),
                                ),
                              )
                            else if (since != null)
                              Flexible(
                                child: CallTimerSuffix(
                                  since: since,
                                  style: style,
                                ),
                              ),
                          ],
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
                          returnToCallLabel,
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
