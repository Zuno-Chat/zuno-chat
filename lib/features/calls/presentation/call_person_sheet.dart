import 'package:flutter/material.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';
import '../../room_info/presentation/remove_member_dialog.dart';

enum _PersonAction { mute, remove }

Future<void> showCallPersonOptions(
  BuildContext context,
  ActiveCallController call,
  CallEngineParticipant participant,
) async {
  final l10n = context.l10n;
  final name = call.userOf(participant.id.userId).calcDisplayname();
  final action = await showActionSheet<_PersonAction>(
    context,
    title: name,
    actions: [
      if (!participant.audioMuted)
        SheetAction(
          _PersonAction.mute,
          icon: Icons.mic_off_outlined,
          label: l10n.callsMutePerson,
        ),
      SheetAction(
        _PersonAction.remove,
        icon: Icons.person_remove_outlined,
        label: l10n.callsRemoveFromCall,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PersonAction.mute:
      await attempt(
        context,
        () => call.mute(participant),
        label: 'mute someone in a call',
        failed: l10n.callsMutePersonFailed(name),
      );
    case _PersonAction.remove:
      final confirmed = await confirmRemoveMember(
        context,
        name: name,
        place: RemoveMemberPlace.call,
      );
      if (!confirmed || !context.mounted) return;
      await attempt(
        context,
        () => call.remove(participant),
        label: 'remove someone from a call',
        failed: l10n.callsRemovePersonFailed(name),
      );
  }
}
