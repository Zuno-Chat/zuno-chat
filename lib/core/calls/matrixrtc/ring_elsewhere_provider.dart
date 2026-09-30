import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/matrix_client_provider.dart';
import '../platform/incoming_call_presenter.dart';
import '../platform/system_ring.dart';
import 'call_member_state.dart';
import 'call_summary_message.dart';
import 'resolved_call_ids_provider.dart';

bool answeredOnAnotherDevice(Room room, String callId) {
  final client = room.client;
  final own = room.states[callMemberEventType]?[client.userID];
  return parseRtcMemberships(own?.content)
      .any((m) => m.callId == callId && m.deviceId != client.deviceID);
}

bool declinedByMe(Event event, SystemRingingCall ring) =>
    event.room.id == ring.roomId &&
    event.senderId == event.room.client.userID &&
    event.messageType == callDeclineMsgtype &&
    event.content.tryGet<String>('call_id') == ring.callId;

final ringElsewhereProvider = Provider<void>((ref) {
  final client = ref.watch(matrixClientProvider);

  void resolve(SystemRingingCall ring, RingEnd end) {
    if (SystemRing.instance.ringing.value != ring) return;
    SystemRing.instance.clear(ring.callId);
    ref.read(resolvedCallIdsProvider.notifier).markResolved(ring.callId);
    unawaited(
      ref
          .read(incomingCallPresenterProvider)
          .cancelIncoming(roomId: ring.roomId, callId: ring.callId, end: end),
    );
  }

  void checkAnswered() {
    final ring = SystemRing.instance.ringing.value;
    if (ring == null) return;
    final room = client.getRoomById(ring.roomId);
    if (room == null || !answeredOnAnotherDevice(room, ring.callId)) return;
    resolve(ring, RingEnd.answeredElsewhere);
  }

  void checkAnsweredSoon() => scheduleMicrotask(checkAnswered);

  final syncSub = client.onSync.stream.listen((_) => checkAnswered());
  SystemRing.instance.ringing.addListener(checkAnsweredSoon);
  final declineSub = client.onTimelineEvent.stream.listen((event) {
    final ring = SystemRing.instance.ringing.value;
    if (ring == null || !declinedByMe(event, ring)) return;
    resolve(ring, RingEnd.declinedElsewhere);
  });
  ref.onDispose(() {
    SystemRing.instance.ringing.removeListener(checkAnsweredSoon);
    unawaited(syncSub.cancel());
    unawaited(declineSub.cancel());
  });
});
