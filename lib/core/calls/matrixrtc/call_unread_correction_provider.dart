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
    final sub = client.onTimelineEvent.stream.listen(_handleEvent);
    ref.onDispose(sub.cancel);
    return {};
  }

  void _handleEvent(Event event) {
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
