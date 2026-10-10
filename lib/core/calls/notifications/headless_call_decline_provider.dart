import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/caught_errors.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../notifications/message_notification_action.dart';
import '../matrixrtc/call_decline.dart';
import '../matrixrtc/resolved_call_ids_provider.dart';
import '../platform/incoming_call_presenter.dart';
import 'call_notification_service.dart';

final headlessCallDeclineProvider =
    NotifierProvider<HeadlessCallDeclineNotifier, void>(
      HeadlessCallDeclineNotifier.new,
    );

class HeadlessCallDeclineNotifier extends Notifier<void> {
  @override
  void build() {
    final sub = CallNotificationService.instance.onHeadlessDecline.listen(
      _handle,
    );
    ref.onDispose(sub.cancel);
  }

  Future<void> _handle(HeadlessCallDecline decline) async {
    final presenter = ref.read(incomingCallPresenterProvider);
    final resolved = ref.read(resolvedCallIdsProvider.notifier);
    final room = ref.read(matrixClientProvider).getRoomById(decline.roomId);
    try {
      await presenter.cancelIncoming(
        roomId: decline.roomId,
        callId: decline.callId,
        end: RingEnd.declinedElsewhere,
      );
      resolved.markResolved(decline.callId);
      if (room == null) return;
      await retryNotificationAction(
        () => declineCallOrFail(room, decline.callId),
      );
    } catch (e, s) {
      reportCaught('decline a call handed from the background', e, s);
    } finally {
      decline.finished();
    }
  }
}
