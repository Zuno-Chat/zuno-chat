import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/ui/alert_banner.dart';

class PendingInviteBanner extends StatelessWidget {
  final Room room;

  const PendingInviteBanner({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    if (!isAwaitingInviteAcceptance(room)) return const SizedBox.shrink();

    return InfoStrip(
      icon: Icons.schedule_outlined,
      title: pendingInviteSubtitle(room, context.l10n),
      body: context.l10n.chatPendingInviteHint,
    );
  }
}
