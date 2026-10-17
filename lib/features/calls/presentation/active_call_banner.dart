import 'package:flutter/material.dart';

import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/l10n/l10n.dart';

class ActiveCallBanner extends StatelessWidget {
  final ActiveRoomCall call;
  final VoidCallback onJoin;

  const ActiveCallBanner({super.key, required this.call, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isVideo = call.kind == CallKind.video.name;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: onJoin,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isVideo
                      ? context.l10n.chatVideoCallInProgress
                      : context.l10n.chatVoiceCallInProgress,
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: onJoin,
                child: Text(context.l10n.commonJoin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
