import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/call_decline.dart';
import '../../../core/calls/matrixrtc/call_session.dart';
import '../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../core/calls/matrixrtc/incoming_call.dart';
import '../../../core/calls/matrixrtc/resolved_call_ids_provider.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/calls/notifications/pending_call_notification_action_provider.dart';
import '../../../core/calls/notifications/ringing_call_provider.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_user_display.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/zuno_colors.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_page.dart';
import 'call_stage.dart';

class IncomingCallPage extends ConsumerStatefulWidget {
  final IncomingCall call;

  const IncomingCallPage({required this.call, super.key});

  @override
  ConsumerState<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends ConsumerState<IncomingCallPage> {
  StreamSubscription<CallNotificationResponse>? _notificationActionSub;
  StreamSubscription<Event>? _callEndedSub;
  bool _resolved = false;
  User? _caller;
  bool _handedOffToCall = false;

  @override
  void initState() {
    super.initState();
    RingingCall.instance.set(widget.call.callId);
    _caller = widget.call.room.unsafeGetUserFromMemoryOrFallback(
      widget.call.callerId,
    );
    unawaited(_resolveCaller());
    ref.listenManual(resolvedCallIdsProvider, (previous, next) {
      if (_resolved || !next.contains(widget.call.callId)) return;
      _resolved = true;
      _dismiss();
    });
    if (ref.read(resolvedCallIdsProvider).contains(widget.call.callId)) {
      _resolved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismiss());
      return;
    }
    if (ref.read(activeCallProvider)?.callId == widget.call.callId) {
      _resolved = true;
      _handedOffToCall = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismiss());
      return;
    }
    final pendingAction = ref.read(pendingCallNotificationActionProvider);
    if (pendingAction != null &&
        pendingAction.call.callId == widget.call.callId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingCallNotificationActionProvider.notifier).consume();
        _runAction(pendingAction.action);
      });
      return;
    }
    unawaited(CallNotificationService.instance.setShowOverLockscreen(true));
    _notificationActionSub = CallNotificationService.instance.onAction.listen((
      response,
    ) {
      if (response.call.callId != widget.call.callId) return;
      _runAction(response.action);
    });
    _callEndedSub = widget.call.room.client.onTimelineEvent.stream.listen(
      _handleCallEnded,
    );
  }

  void _runAction(CallNotificationAction action) {
    switch (action) {
      case CallNotificationAction.accept:
        _accept();
      case CallNotificationAction.decline:
        _decline();
    }
  }

  Future<void> _resolveCaller() async {
    final caller = await resolveRoomUser(
      widget.call.room,
      widget.call.callerId,
      allowNetwork: true,
    );
    if (!mounted) return;
    setState(() => _caller = caller);
  }

  @override
  void dispose() {
    _notificationActionSub?.cancel();
    _callEndedSub?.cancel();
    unawaited(CallNotificationService.instance.cancelIncomingCall());
    RingingCall.instance.clear(widget.call.callId);
    if (!_handedOffToCall) {
      unawaited(CallNotificationService.instance.setShowOverLockscreen(false));
    }
    super.dispose();
  }

  void _handleCallEnded(Event event) {
    if (_resolved) return;
    if (event.room.id != widget.call.room.id) return;
    if (!isCallSummaryMessage(event.messageType)) return;
    if (event.content.tryGet<String>('call_id') != widget.call.callId) return;
    _resolved = true;
    _dismiss();
  }

  void _dismiss() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  Future<void> _accept() async {
    if (_resolved) return;
    _resolved = true;
    if (ref.read(activeCallProvider) != null) {
      _handedOffToCall = true;
      _dismiss();
      return;
    }
    final session = CallSession.forIncoming(
      room: widget.call.room,
      callId: widget.call.callId,
      kind: widget.call.kind,
      lowDataMode: ref.read(lowDataCallsProvider),
    );
    ref.read(activeCallProvider.notifier).set(session);
    _handedOffToCall = true;
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CallPage(session: session)),
      ),
    );
    unawaited(session.accept().catchError((_) {}));
  }

  Future<void> _decline() async {
    if (_resolved) return;
    _resolved = true;
    await declineCall(widget.call.room, widget.call.callId);
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final caller =
        _caller ?? call.room.unsafeGetUserFromMemoryOrFallback(call.callerId);

    final name = caller.calcDisplayname();
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Theme(
          data: zunoDarkTheme,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: CallPortrait(
                          avatarBuilder: (radius) => MxcAvatar(
                            client: call.room.client,
                            avatarUrl: caller.avatarUrl,
                            fallbackText: name,
                            toneSeed: caller.id,
                            radius: radius,
                          ),
                          name: name,
                          details: [
                            Text(
                              call.kind == CallKind.video
                                  ? 'Incoming video call'
                                  : 'Incoming voice call',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(48, 8, 48, 32),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _RingActionButton(
                              icon: Icons.call_end,
                              color: callEndColor,
                              label: 'Decline',
                              onPressed: _decline,
                            ),
                            _RingActionButton(
                              icon: call.kind == CallKind.video
                                  ? Icons.videocam
                                  : Icons.call,
                              color: callAcceptColor,
                              label: 'Accept',
                              onPressed: _accept,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  const _RingActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          iconSize: 30,
          tooltip: label,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: onCallActionColor,
            fixedSize: const Size(72, 72),
          ),
          onPressed: onPressed,
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    );
  }
}
