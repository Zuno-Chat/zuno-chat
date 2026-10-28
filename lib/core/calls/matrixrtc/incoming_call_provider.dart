import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/late_decryptions.dart';
import '../../matrix/matrix_client_provider.dart';
import '../models/call_kind.dart';
import '../notifications/server_ring.dart';
import 'call_member_state.dart';
import 'call_summary_message.dart';
import 'incoming_call.dart';

const _maxInviteAge = Duration(seconds: 45);
const _ringBurst = 8;
const _ringWindow = Duration(minutes: 1);

class RingRateLimiter {
  final int burst;
  final Duration window;
  final _recentBySender = <String, List<DateTime>>{};
  static const _maxTracked = 64;

  RingRateLimiter({this.burst = _ringBurst, this.window = _ringWindow});

  bool allow(String senderId) {
    final at = clock.now();
    final times = _recentBySender.remove(senderId) ?? <DateTime>[];
    times.removeWhere((t) => at.difference(t) >= window);
    final allowed = times.length < burst;
    if (allowed) times.add(at);
    _recentBySender[senderId] = times;
    if (_recentBySender.length > _maxTracked) {
      _recentBySender.remove(_recentBySender.keys.first);
    }
    return allowed;
  }

  void clear() => _recentBySender.clear();
}

final ringRateLimiter = RingRateLimiter();

IncomingCall? incomingCallFromEvent(Client client, Event event) {
  if (event.senderId == client.userID) return null;
  if (event.messageType != callInviteMsgtype) return null;
  if (clock.now().difference(event.originServerTs) > _maxInviteAge) {
    return null;
  }

  final callId = event.content.tryGet<String>('call_id');
  final kindName = event.content.tryGet<String>('kind');
  if (callId == null || kindName == null) return null;
  if (!canPublishCallMemberState(event.room)) return null;
  if (!ringRateLimiter.allow(event.senderId)) return null;

  return IncomingCall(
    room: event.room,
    callId: callId,
    callerId: event.senderId,
    kind: CallKind.values.asNameMap()[kindName] ?? CallKind.voice,
  );
}

const _maxRememberedCallIds = 128;

final incomingCallProvider = StreamProvider<IncomingCall>((ref) {
  final client = ref.watch(matrixClientProvider);
  final seenCallIds = <String>{};
  final calls = StreamController<IncomingCall>();

  void ring(IncomingCall? call) {
    if (call == null || !seenCallIds.add(call.callId)) return;
    if (seenCallIds.length > _maxRememberedCallIds) {
      seenCallIds.remove(seenCallIds.first);
    }
    calls.add(call);
  }

  final subscriptions = [
    LateDecryptions.of(client).timeline
        .listen((event) => ring(incomingCallFromEvent(client, event))),
    ref
        .watch(serverRingsProvider)
        .stream
        .listen((pushed) => ring(incomingCallFromServerRing(client, pushed))),
  ];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(calls.close());
  });
  return calls.stream;
});
