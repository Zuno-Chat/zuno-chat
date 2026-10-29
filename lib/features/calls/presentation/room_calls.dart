import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/matrixrtc/call_session.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/connectivity_provider.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';
import 'call_page.dart';

Future<void> startRoomCall(
  BuildContext context,
  WidgetRef ref,
  Room room,
  CallKind kind,
) async {
  if (_busyWithCall(context, ref, room)) return;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (!canPublishCallMemberState(room)) {
    messenger.say(l10n.callsFailureNoPermission);
    return;
  }
  if (!hasSomeoneToCall(room)) {
    messenger.say(l10n.chatNobodyJoined);
    return;
  }
  if (ref.read(isOfflineProvider).value ?? false) {
    messenger.say(l10n.chatNoConnection);
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
  final messenger = ScaffoldMessenger.of(context);
  if (!canPublishCallMemberState(room)) {
    messenger.say(l10n.chatNoJoinCallPermission);
    return;
  }
  if (ref.read(isOfflineProvider).value ?? false) {
    messenger.say(l10n.chatNoConnection);
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
    ScaffoldMessenger.of(context).say(context.l10n.chatAlreadyInCall);
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

Future<bool> _confirmCall(BuildContext context, Room room, CallKind kind) {
  final l10n = context.l10n;
  return confirm(
    context,
    title: l10n.chatCallTitle(roomTitle(room, l10n)),
    body: kind == CallKind.video
        ? l10n.chatStartVideoCall
        : l10n.chatStartVoiceCall,
    confirmLabel: l10n.callsStartCall,
  );
}
