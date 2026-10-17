import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/matrixrtc/call_session.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/connectivity_provider.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/settings/app_preferences_provider.dart';
import 'call_page.dart';

Future<void> startRoomCall(
  BuildContext context,
  WidgetRef ref,
  Room room,
  CallKind kind,
) async {
  if (_busyWithCall(context, ref, room)) return;
  final l10n = context.l10n;
  if (!canPublishCallMemberState(room)) {
    _say(context, l10n.callsFailureNoPermission);
    return;
  }
  if (!hasSomeoneToCall(room)) {
    _say(context, l10n.chatNobodyJoined);
    return;
  }
  if (ref.read(isOfflineProvider).value ?? false) {
    _say(context, l10n.chatNoConnection);
    return;
  }
  if (ref.read(confirmBeforeCallingProvider)) {
    final confirmed = await _confirmCall(context, room, kind);
    if (!confirmed || !context.mounted) return;
  }
  final session = ref
      .read(activeCallProvider.notifier)
      .start(
        () => CallSession.startOutgoing(
          room,
          kind,
          lowDataMode: ref.read(lowDataCallsProvider),
        ),
      );
  _openCall(context, ref, room, session);
}

void joinRoomCall(
  BuildContext context,
  WidgetRef ref,
  Room room,
  ActiveRoomCall call,
) {
  if (_busyWithCall(context, ref, room)) return;
  final l10n = context.l10n;
  if (!canPublishCallMemberState(room)) {
    _say(context, l10n.chatNoJoinCallPermission);
    return;
  }
  if (ref.read(isOfflineProvider).value ?? false) {
    _say(context, l10n.chatNoConnection);
    return;
  }
  final session = ref
      .read(activeCallProvider.notifier)
      .join(
        room: room,
        callId: call.callId,
        kind: CallKind.values.asNameMap()[call.kind] ?? CallKind.voice,
      );
  _openCall(context, ref, room, session)?.accept().ignore();
}

bool _busyWithCall(BuildContext context, WidgetRef ref, Room room) {
  final active = ref.read(activeCallProvider);
  if (active == null || active.phase == CallSessionPhase.ended) return false;
  final call = active.room.id == room.id
      ? ref.read(activeCallControllerProvider)
      : null;
  if (call != null) {
    showCallScreen(Navigator.of(context), call);
  } else {
    _say(context, context.l10n.chatAlreadyInCall);
  }
  return true;
}

CallSession? _openCall(
  BuildContext context,
  WidgetRef ref,
  Room room,
  CallSession? session,
) {
  if (session == null) {
    _busyWithCall(context, ref, room);
    return null;
  }
  final call = ref.read(activeCallControllerProvider);
  if (call != null) showCallScreen(Navigator.of(context), call);
  return session;
}

Future<bool> _confirmCall(
  BuildContext context,
  Room room,
  CallKind kind,
) async {
  final name = roomTitle(room, context.l10n);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.chatCallTitle(name)),
      content: Text(
        kind == CallKind.video
            ? context.l10n.chatStartVideoCall
            : context.l10n.chatStartVoiceCall,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.callsStartCall),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void _say(BuildContext context, @displayText String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
