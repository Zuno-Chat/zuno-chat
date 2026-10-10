import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../features/calls/presentation/incoming_call_page.dart';
import '../errors/global_error_handler.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/room_title.dart';
import '../matrix/room_user_display.dart';
import '../navigation/global_navigator.dart';
import '../platform/platform_capabilities.dart';
import '../push/read_model/read_model_publisher.dart';
import '../push/voip/launch_channel.dart';
import '../push/voip/voip_registration.dart';
import 'active_call_provider.dart';
import 'call_liveness.dart';
import 'matrixrtc/call_member_state.dart';
import 'matrixrtc/call_waiting.dart';
import 'matrixrtc/incoming_call.dart';
import 'matrixrtc/incoming_call_provider.dart';
import 'matrixrtc/resolved_call_ids_provider.dart';
import 'matrixrtc/resolved_call_ids_store.dart';
import 'matrixrtc/ring_elsewhere_provider.dart';
import 'models/call_kind.dart';
import 'notifications/call_notification_router.dart';
import 'notifications/call_notification_service.dart';
import 'notifications/ring_notification.dart';
import 'notifications/ringing_call_provider.dart';
import 'platform/incoming_call_presenter.dart';
import 'platform/native_ring.dart';
import 'platform/push_ring_bridge.dart';
import 'platform/system_call.dart';
import 'platform/system_ring.dart';

const genericBindWindow = Duration(seconds: 20);
const freshCallWindow = Duration(seconds: 45);

typedef FreshCall = ({IncomingCall call, int startedMs});

FreshCall? newestFreshCall(
  Client client, {
  required DateTime now,
  Duration window = freshCallWindow,
}) {
  FreshCall? newest;
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    final starts = <String, ({int at, String callerId, CallKind kind})>{};
    final mine = <String>{};
    final states = room.states[callMemberEventType] ?? const {};
    for (final MapEntry(key: userId, value: state) in states.entries) {
      for (final membership in rawMemberships(state.content)) {
        if (userId == client.userID) {
          mine.add(membership.callId);
          continue;
        }
        final known = starts[membership.callId];
        if (known == null || membership.createdTs < known.at) {
          starts[membership.callId] = (
            at: membership.createdTs,
            callerId: userId,
            kind: membership.kind,
          );
        }
      }
    }
    for (final MapEntry(key: callId, value: start) in starts.entries) {
      if (mine.contains(callId)) continue;
      if (now.millisecondsSinceEpoch - start.at > window.inMilliseconds) {
        continue;
      }
      if (newest != null && newest.startedMs >= start.at) continue;
      newest = (
        call: IncomingCall(
          room: room,
          callId: callId,
          callerId: start.callerId,
          kind: start.kind,
        ),
        startedMs: start.at,
      );
    }
  }
  return newest;
}

Future<String> ringName(IncomingCall call) async {
  if (!call.room.isDirectChat) return roomTitle(call.room);
  final caller = await resolveRoomUser(call.room, call.callerId);
  return caller.calcDisplayname();
}

final ringCoordinatorProvider = NotifierProvider<RingCoordinator, void>(
  RingCoordinator.new,
);

final pushRingServicesProvider = Provider<void>((ref) {
  if (!ref.watch(platformCapabilitiesProvider).voipRing) return;
  ref.watch(ringCoordinatorProvider);
  ref.watch(readModelPublisherProvider);
  ref.watch(voipLifecycleProvider);
});

class RingCoordinator extends Notifier<void> {
  final _pushRung = <String>{};
  final _syncRung = <String>{};
  NativeRing? _pendingGeneric;
  Timer? _genericDeadline;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  @override
  void build() {
    if (!ref.watch(platformCapabilitiesProvider).voipRing) return;
    final client = ref.watch(matrixClientProvider);
    ref.watch(callNotificationRouterProvider);
    ref.watch(ringElsewhereProvider);
    ref.listen(resolvedCallIdsProvider, (_, _) {});
    final notifications = CallNotificationService.instance;
    final subscriptions = [
      notifications.onAction.listen(
        (response) => unawaited(_onAction(response)),
      ),
      notifications.onNativeRing.listen(
        (ring) => unawaited(_onNativeRing(ring)),
      ),
      client.onSync.stream.listen((_) => _bindPendingGeneric()),
    ];
    ref.listen<AsyncValue<IncomingCall>>(incomingCallProvider, (_, next) {
      final call = next.value;
      if (call != null) unawaited(_onIncomingCall(call));
    });
    SystemRing.instance.ringing.addListener(_forgetEndedSyncRings);
    ref.onDispose(() {
      SystemRing.instance.ringing.removeListener(_forgetEndedSyncRings);
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      _genericDeadline?.cancel();
    });
    unawaited(_takeLaunchState(notifications));
  }

  Future<void> _takeLaunchState(CallNotificationService notifications) async {
    await notifications.takeQueuedNativeCalls();
    const launch = LaunchChannel();
    final reason = await launch.takeWakeReason();
    if (reason != null) debugPrint('zuno/ring: woken for ${reason.name}');
  }

  bool _resolvedNow(String callId) =>
      RingingCall.instance.callId == callId ||
      ref.read(resolvedCallIdsProvider).contains(callId);

  bool _systemRingBusy(String callId) {
    final ringing = SystemRing.instance.ringing.value;
    return ringing != null && ringing.callId != callId;
  }

  void _forgetEndedSyncRings() {
    final ringing = SystemRing.instance.ringing.value?.callId;
    _syncRung.removeWhere((callId) => callId != ringing);
  }

  Future<void> _onIncomingCall(IncomingCall call) async {
    if (_resolvedNow(call.callId) || await isCallResolved(call.callId)) return;
    if (_resolvedNow(call.callId)) return;
    final presenter = ref.read(incomingCallPresenterProvider);
    if (answeredOnAnotherDevice(call.room, call.callId)) {
      ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
      unawaited(
        presenter.cancelIncoming(
          roomId: call.room.id,
          callId: call.callId,
          end: RingEnd.answeredElsewhere,
        ),
      );
      return;
    }
    if (_pushRung.contains(call.callId)) {
      await ref
          .read(pushRingBridgeProvider)
          .updateIncoming(
            roomId: call.room.id,
            callId: call.callId,
            name: await ringName(call),
            video: call.kind == CallKind.video,
          );
      return;
    }
    if (ref.read(activeCallProvider) != null || _systemRingBusy(call.callId)) {
      unawaited(autoDeclineIncomingCall(call));
      ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
      final callerName = call.room
          .unsafeGetUserFromMemoryOrFallback(call.callerId)
          .calcDisplayname();
      globalScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Missed call from $callerName')),
      );
      return;
    }
    final generic = _pendingGeneric;
    if (generic != null) {
      await _bindGeneric(generic, call);
      return;
    }
    _syncRung.add(call.callId);
    SystemRing.instance.set(roomId: call.room.id, callId: call.callId);
    var outcome = RingOutcome.unavailable;
    try {
      outcome = await postRingNotification(call, presenter: presenter);
    } finally {
      if (outcome != RingOutcome.shown) SystemRing.instance.clear(call.callId);
    }
    if (outcome != RingOutcome.unavailable) return;
    unawaited(
      globalNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => IncomingCallPage(call: call)),
      ),
    );
  }

  Future<void> _onNativeRing(NativeRing ring) async {
    final roomId = ring.roomId;
    final callId = ring.callId;
    if (roomId == null || callId == null) {
      if (ring.source == NativeRingSource.generic) _awaitBinding(ring);
      return;
    }
    if (ring.source != NativeRingSource.sync) _pushRung.add(callId);
    SystemRing.instance.set(roomId: roomId, callId: callId);
    if (!_resolvedNow(callId) && !await isCallResolved(callId)) return;
    await ref
        .read(incomingCallPresenterProvider)
        .cancelIncoming(roomId: roomId, callId: callId);
  }

  void _awaitBinding(NativeRing ring) {
    _pendingGeneric = ring;
    _genericDeadline?.cancel();
    _genericDeadline = Timer(genericBindWindow, () {
      if (_pendingGeneric?.uuid != ring.uuid) return;
      _pendingGeneric = null;
      unawaited(ref.read(pushRingBridgeProvider).endUnbound(ring.uuid));
    });
    _bindPendingGeneric();
  }

  void _bindPendingGeneric() {
    final generic = _pendingGeneric;
    if (generic == null) return;
    final fresh = newestFreshCall(ref.read(matrixClientProvider), now: now());
    if (fresh == null) return;
    unawaited(_bindGeneric(generic, fresh.call));
  }

  Future<void> _bindGeneric(NativeRing generic, IncomingCall call) async {
    if (_pendingGeneric?.uuid != generic.uuid) return;
    if (_resolvedNow(call.callId) || await isCallResolved(call.callId)) return;
    if (_pendingGeneric?.uuid != generic.uuid) return;
    _pendingGeneric = null;
    _genericDeadline?.cancel();
    final bound = await ref
        .read(pushRingBridgeProvider)
        .bindIncoming(
          uuid: generic.uuid,
          roomId: call.room.id,
          callId: call.callId,
          callerId: call.callerId,
          name: await ringName(call),
          video: call.kind == CallKind.video,
        );
    if (!bound) return;
    _pushRung.add(call.callId);
    SystemRing.instance.set(roomId: call.room.id, callId: call.callId);
  }

  Future<void> _onAction(CallNotificationResponse response) async {
    final router = ref.read(callNotificationRouterProvider.notifier);
    final call = response.call;
    if (response.action == CallNotificationAction.decline) {
      try {
        await router.handle(response);
      } finally {
        await ref
            .read(pushRingBridgeProvider)
            .declineSent(roomId: call.roomId, callId: call.callId);
      }
      return;
    }
    if (_syncRung.contains(call.callId)) {
      await router.handle(response);
      return;
    }
    final liveness = await checkCallLiveness(
      ref.read(matrixClientProvider),
      roomId: call.roomId,
      callId: call.callId,
      callerId: call.callerId,
    );
    if (liveness == CallLiveness.gone) {
      ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
      SystemRing.instance.clear(call.callId);
      await ref
          .read(systemCallProvider)
          .end(
            roomId: call.roomId,
            callId: call.callId,
            end: SystemCallEnd.remoteEnded,
            byUser: false,
          );
      return;
    }
    await router.handle(response);
  }
}
