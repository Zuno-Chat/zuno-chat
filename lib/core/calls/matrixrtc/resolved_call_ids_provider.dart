import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/matrix_client_provider.dart';
import '../../settings/app_preferences_provider.dart';
import '../notifications/call_notification_service.dart';
import 'call_summary_message.dart';
import 'resolved_call_ids_store.dart';

final resolvedCallIdsProvider =
    NotifierProvider<ResolvedCallIdsNotifier, Set<String>>(
      ResolvedCallIdsNotifier.new,
    );

class ResolvedCallIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onTimelineEvent.stream.listen(_handleEvent);
    ref.onDispose(sub.cancel);
    return readResolvedCallIds(ref.read(sharedPreferencesProvider));
  }

  void _handleEvent(Event event) {
    if (!isCallSummaryMessage(event.messageType)) return;
    final callId = event.content.tryGet<String>('call_id');
    if (callId == null) return;
    markResolved(callId);
    unawaited(CallNotificationService.instance.cancelIncomingCall());
  }

  void markResolved(String callId) {
    state = {...state, callId};
    unawaited(
      markCallResolvedOnDisk(
        ref.read(sharedPreferencesProvider),
        callId,
      ).catchError((_) {}),
    );
  }
}
