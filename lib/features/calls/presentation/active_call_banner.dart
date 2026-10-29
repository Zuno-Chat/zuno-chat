import 'package:flutter/material.dart';

import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/ui/alert_banner.dart';

class ActiveCallBanner extends StatelessWidget {
  final ActiveRoomCall call;
  final VoidCallback onJoin;

  const ActiveCallBanner({super.key, required this.call, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final isVideo = call.kind == CallKind.video.name;
    return InfoStrip(
      icon: isVideo ? Icons.videocam_outlined : Icons.call_outlined,
      title: isVideo
          ? context.l10n.chatVideoCallInProgress
          : context.l10n.chatVoiceCallInProgress,
      actionLabel: context.l10n.commonJoin,
      onAction: onJoin,
      onTap: onJoin,
    );
  }
}
