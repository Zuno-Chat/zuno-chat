import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/event_display.dart';
import '../../matrix/matrix_client_provider.dart';
import 'call_summary_message.dart';

final callUnreadCorrectionProvider =
    NotifierProvider<CallUnreadCorrectionNotifier, Map<String, int>>(
      CallUnreadCorrectionNotifier.new,
    );

class CallUnreadCorrectionNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    final client = ref.watch(matrixClientProvider);
    final events = client.onTimelineEvent.stream.listen(_handleEvent);
    final syncs = client.onSync.stream.listen((_) => _keepWithinCount(client));
    ref.onDispose(() {
      unawaited(events.cancel());
      unawaited(syncs.cancel());
    });
    return {};
  }

  void _keepWithinCount(Client client) {
    final kept = <String, int>{};
    for (final MapEntry(key: roomId, value: correction) in state.entries) {
      final counted = client.getRoomById(roomId)?.notificationCount ?? 0;
      if (counted > 0) kept[roomId] = min(correction, counted);
    }
    if (!mapEquals(kept, state)) state = kept;
  }

  void _handleEvent(Event event) {
    if (event.senderId == event.room.client.userID) return;
    if (event.relationshipType == RelationshipTypes.reference) return;
    final hidesFromTimeline =
        event.type == EventTypes.Message &&
        event.relationshipType != RelationshipTypes.edit &&
        !isDisplayableTimelineEvent(event, showHiddenMessages: false);
    final isAnsweredSummary =
        isCallSummaryMessage(event.messageType) &&
        CallSummary.fromEvent(event)?.status == CallSummaryStatus.ended;
    if (!hidesFromTimeline && !isAnsweredSummary) return;
    final roomId = event.room.id;
    state = {...state, roomId: (state[roomId] ?? 0) + 1};
  }

  void clearFor(String roomId) {
    if (!state.containsKey(roomId)) return;
    state = {...state}..remove(roomId);
  }
}

int displayedUnreadCount(Map<String, int> corrections, Room room) {
  final corrected = room.notificationCount - (corrections[room.id] ?? 0);
  return corrected < 0 ? 0 : corrected;
}
