import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_notification_service.dart';

final pendingCallNotificationActionProvider =
    NotifierProvider<
      PendingCallNotificationActionNotifier,
      CallNotificationResponse?
    >(PendingCallNotificationActionNotifier.new);

class PendingCallNotificationActionNotifier
    extends Notifier<CallNotificationResponse?> {
  @override
  CallNotificationResponse? build() {
    final sub = CallNotificationService.instance.onAction.listen((response) {
      state = response;
    });
    ref.onDispose(sub.cancel);
    return null;
  }

  CallNotificationResponse? consume() {
    final response = state;
    state = null;
    return response;
  }
}
