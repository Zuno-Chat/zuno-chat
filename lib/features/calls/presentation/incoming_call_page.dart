import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/call_waiting_provider.dart';
import '../../../core/calls/matrixrtc/call_decline.dart';
import '../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../core/calls/matrixrtc/incoming_call.dart';
import '../../../core/calls/matrixrtc/resolved_call_ids_provider.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/calls/notifications/pending_call_notification_action_provider.dart';
import '../../../core/calls/notifications/ringing_call_provider.dart';
import '../../../core/calls/platform/incoming_call_presenter.dart';
import '../../../core/calls/platform/system_ring.dart';
import '../../../core/calls/ring_identity.dart';
import '../../../core/calls/show_over_lockscreen.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/ui/close_own_route.dart';
import '../../../core/ui/zuno_colors.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_bar.dart';
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
  late final IncomingCallPresenter _incomingCallPresenter;
  late final bool _ownsRing;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _incomingCallPresenter = ref.read(incomingCallPresenterProvider);
    _ownsRing = !ref.read(platformCapabilitiesProvider).callKit;
    RingingCall.instance.set(widget.call.callId);
    unawaited(_loadIdentity());
    ref.listenManual(resolvedCallIdsProvider, (previous, next) {
      if (_resolved || !next.contains(widget.call.callId)) return;
      _resolved = true;
      _dismiss();
    });
    final answeredHere =
        ref.read(activeCallProvider)?.callId == widget.call.callId;
    if (answeredHere ||
        ref.read(resolvedCallIdsProvider).contains(widget.call.callId)) {
      _resolved = true;
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
    ShowOverLockscreen.instance.claim(this);
    if (_ownsRing) {
      SystemRing.instance.set(
        roomId: widget.call.room.id,
        callId: widget.call.callId,
      );
    }
    _notificationActionSub = CallNotificationService.instance.onAction.listen((
      response,
    ) {
      if (response.call.callId != widget.call.callId) return;
      _runAction(response.action);
    });
    _callEndedSub = widget.call.room.client.onTimelineEvent.stream.listen(
      _handleCallEnded,
    );
    ref.listenManual<String?>(
      callWaitingProvider,
      (_, _) => _ringAloudUnlessWaiting(),
      fireImmediately: true,
    );
  }

  void _ringAloudUnlessWaiting() {
    final callId = widget.call.callId;
    if (_resolved) return;
    if (waitingRing(ref.read(activeCallProvider), callId) != null) return;
    if (SystemRing.instance.ringing.value?.callId != callId) return;
    unawaited(_incomingCallPresenter.ringAloud(callId));
  }

  void _runAction(CallNotificationAction action) {
    switch (action) {
      case CallNotificationAction.accept:
        _accept();
      case CallNotificationAction.decline:
        _decline();
    }
  }

  Future<void> _loadIdentity() async {
    await loadRingIdentity(widget.call, allowNetwork: true);
    if (mounted) setState(() {});
  }

  void _releaseRing() {
    if (_ownsRing) SystemRing.instance.clear(widget.call.callId);
  }

  @override
  void dispose() {
    _releaseRing();
    _notificationActionSub?.cancel();
    _callEndedSub?.cancel();
    unawaited(
      _incomingCallPresenter.cancelIncoming(
        roomId: widget.call.room.id,
        callId: widget.call.callId,
      ),
    );
    RingingCall.instance.clear(widget.call.callId);
    ShowOverLockscreen.instance.release(this);
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
    _releaseRing();
    if (mounted) closeOwnRoute(context);
  }

  void _accept() {
    if (_resolved) return;
    _resolved = true;
    final session = ref.read(activeCallProvider.notifier).answer(widget.call);
    if (session == null) {
      _dismiss();
      return;
    }
    _releaseRing();
    if (!mounted) return;
    final call = ref.read(activeCallControllerProvider);
    if (call != null) {
      ShowOverLockscreen.instance.claim(call);
      showCallScreen(Navigator.of(context), call, replace: true);
    }
    session.accept().ignore();
  }

  void _decline() {
    if (_resolved) return;
    _resolved = true;
    final IncomingCall(:room, :callId) = widget.call;
    ref.read(resolvedCallIdsProvider.notifier).markResolved(callId);
    _dismiss();
    unawaited(
      runBestEffort(
        () => declineCall(room, callId),
        label: 'decline a call from its ring screen',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final identity = ringIdentity(call, context.l10n);
    final waiting = ref.watch(callWaitingProvider) == call.callId;
    final onTheLine = waiting ? ref.watch(activeCallControllerProvider) : null;
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Theme(
          data: zunoDarkTheme,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final l10n = context.l10n;
              return Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      if (onTheLine != null) _CallOnTheLine(call: onTheLine),
                      Expanded(
                        child: CallPortrait(
                          avatarBuilder: (radius) => MxcAvatar(
                            client: call.room.client,
                            avatarUrl: identity.avatarUrl,
                            fallbackText: identity.name,
                            toneSeed: identity.toneSeed,
                            radius: radius,
                          ),
                          name: identity.name,
                          details: [
                            if (identity.caller case final caller?)
                              Text(
                                caller,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium,
                              ),
                            Text(
                              call.kind == CallKind.video
                                  ? l10n.callsIncomingVideo
                                  : l10n.callsIncomingVoice,
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
                            Flexible(
                              child: _RingActionButton(
                                icon: Icons.call_end,
                                color: callEndColor,
                                label: l10n.callsDecline,
                                onPressed: _decline,
                              ),
                            ),
                            Flexible(
                              child: _RingActionButton(
                                icon: call.kind == CallKind.video
                                    ? Icons.videocam
                                    : Icons.call,
                                color: callAcceptColor,
                                label: waiting
                                    ? l10n.callsEndAndAnswer
                                    : l10n.callsAccept,
                                onPressed: _accept,
                              ),
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

class _CallOnTheLine extends StatelessWidget {
  final ActiveCallController call;

  const _CallOnTheLine({required this.call});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: ListenableBuilder(
        listenable: call,
        builder: (context, _) => CallTitleStatus(
          call: call,
          title: l10n.callsOnCallWith(roomTitle(call.session.room, l10n)),
          style: theme.textTheme.bodyMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          alignment: MainAxisAlignment.center,
        ),
      ),
    );
  }
}
