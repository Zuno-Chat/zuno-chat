import 'package:flutter/material.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/l10n.dart';
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
  final action = await showSheet<_PersonAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (!participant.audioMuted)
            ListTile(
              leading: const Icon(Icons.mic_off_outlined),
              title: Text(l10n.callsMutePerson),
              onTap: () => Navigator.of(context).pop(_PersonAction.mute),
            ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: Text(l10n.callsRemoveFromCall),
            onTap: () => Navigator.of(context).pop(_PersonAction.remove),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PersonAction.mute:
      await _attempt(
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
      await _attempt(
        context,
        () => call.remove(participant),
        label: 'remove someone from a call',
        failed: l10n.callsRemovePersonFailed(name),
      );
  }
}

Future<void> _attempt(
  BuildContext context,
  Future<void> Function() action, {
  required String label,
  required String failed,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await action();
  } catch (e, s) {
    reportCaught(label, e, s);
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(l10n, e, failed: failed))),
    );
  }
}
