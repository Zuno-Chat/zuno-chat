import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../matrix/matrix_client_provider.dart';
import '../matrixrtc/call_decline.dart';
import '../matrixrtc/resolved_call_ids_provider.dart';
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
    final client = ref.read(matrixClientProvider);
    final room = client.getRoomById(decline.roomId);
    if (room == null) return;
    await declineCall(room, decline.callId);
    ref.read(resolvedCallIdsProvider.notifier).markResolved(decline.callId);
  }
}
