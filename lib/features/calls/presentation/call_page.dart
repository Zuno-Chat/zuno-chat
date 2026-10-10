import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/calls/models/voip_participant_id.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/navigation/launch_route.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/corner_snap.dart';
import '../../../core/ui/zuno_theme.dart';
import '../../verification/presentation/confirm_person.dart';
import '../../verification/presentation/why_confirm_sheet.dart';
import 'call_confirm_prompt.dart';
import 'call_view.dart';

const cameraDidNotTurnOnMessage =
    'Camera did not turn on. Check that Zuno can use the camera and try again.';

final _screens = Expando<Route<void>>('call screen route');

final _selfCorners = Expando<SnapCorner>('self view corner');

void showCallScreen(
  NavigatorState navigator,
  ActiveCallController call, {
  bool instant = false,
  bool replace = false,
}) {
  if (call.screenOpen || call.finished) return;
  final route = pageRoute<void>(
    instant: instant,
    builder: (_) => CallPage(call: call),
  );
  void closeOnceFinished() {
    if (call.finished) _closeScreen(navigator, route, call);
  }

  _screens[call] = route;
  call.addListener(closeOnceFinished);
  call.screenOpen = true;
  final shown = replace
      ? navigator.pushReplacement<void, Object?>(route)
      : navigator.push<void>(route);
  unawaited(
    shown.whenComplete(() {
      call.removeListener(closeOnceFinished);
      if (identical(_screens[call], route)) _screens[call] = null;
      call.screenOpen = false;
    }),
  );
}

void _closeScreen(
  NavigatorState navigator,
  Route<void> route,
  ActiveCallController call,
) {
  if (!navigator.mounted || !route.isActive) return;
  if (route.isCurrent) {
    navigator.pop();
  } else if (call.replaced) {
    navigator.removeRoute(route);
  } else {
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }
}

Future<T?> pushOverCallScreen<T>(
  NavigatorState navigator,
  ActiveCallController? call,
  Route<T> route,
) {
  final screen = call == null ? null : _screens[call];
  if (screen == null || !screen.isActive) return navigator.push(route);
  navigator.popUntil((r) => r == screen);
  return navigator.pushReplacement<T, Object?>(route);
}

class CallPage extends ConsumerStatefulWidget {
  final ActiveCallController call;

  const CallPage({required this.call, super.key});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  ActiveCallController get call => widget.call;

  @override
  void initState() {
    super.initState();
    if (!call.finished) call.addListener(_onCall);
  }

  void _onCall() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    call.removeListener(_onCall);
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (await call.toggleCamera() || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(cameraDidNotTurnOnMessage)));
  }

  CallViewParticipant _viewOf(CallEngineParticipant participant) =>
      CallViewParticipant(
        participant: participant,
        renderer: call.rendererFor(participant.id),
        user: call.userFor(participant),
        encrypting: call.encrypting(participant),
      );

  @override
  Widget build(BuildContext context) {
    final confirmUserId = _confirmPromptUserId();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: zunoDarkTheme,
        child: _buildCall(context, confirmUserId),
      ),
    );
  }

  String? _confirmPromptUserId() {
    if (!call.session.room.isDirectChat) return null;
    final remotes = call.remotes;
    if (remotes.length != 1) return null;
    final VoipParticipantId(:userId, :deviceId) = remotes.single.id;
    final wanted = callConfirmPromptWanted(
      trust: ref.watch(userTrustProvider(userId)),
      thisDeviceReady: ref.watch(
        accountSecurityFactsProvider.select((facts) {
          final value = facts.value;
          return value != null &&
              value.recoveryExists &&
              value.thisDeviceHasIdentityKeys;
        }),
      ),
      theirDeviceApproved: ref.watch(
        deviceApprovedByOwnerProvider((userId: userId, deviceId: deviceId)),
      ),
      declined: ref.watch(callConfirmPromptStoreProvider).declined(userId),
      talkedLongEnough: call.talkedLongEnough,
    );
    return wanted ? userId : null;
  }

  Future<void> _explainConfirming(BuildContext context, String userId) async {
    final confirm = await showWhyConfirmSheet(
      context,
      name: withoutServer(userId),
    );
    if (confirm == null || !context.mounted) return;
    if (!confirm) {
      await ref.read(callConfirmPromptStoreProvider).decline(userId);
      if (mounted) setState(() {});
      return;
    }
    await confirmPerson(context, ref, userId, picturesFirst: true);
  }

  Widget _buildCall(BuildContext context, String? confirmUserId) {
    final local = call.local;
    return CallView(
      room: call.session.room,
      kind: call.session.kind,
      connecting: call.connecting,
      calling: call.calling,
      local: local == null ? null : _viewOf(local),
      remote: [for (final participant in call.remotes) _viewOf(participant)],
      talkingSince: call.talkingSince,
      reconnecting: call.reconnecting,
      quality: call.quality,
      audioRoute: call.audioRoute,
      onToggleMute: call.toggleMute,
      onToggleCamera: _toggleCamera,
      onSwitchCamera: call.switchCamera,
      onToggleSpeaker: call.toggleSpeaker,
      onHangUp: call.hangUp,
      onMinimize: () => Navigator.of(context).pop(),
      selfCorner: _selfCorners[call] ?? SnapCorner.topRight,
      onSelfCornerChanged: (corner) =>
          setState(() => _selfCorners[call] = corner),
      confirmName: confirmUserId == null ? null : withoutServer(confirmUserId),
      onConfirmPerson: confirmUserId == null
          ? null
          : () => _explainConfirming(context, confirmUserId),
    );
  }
}
