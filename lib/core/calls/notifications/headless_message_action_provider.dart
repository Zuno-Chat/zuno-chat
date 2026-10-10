import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/caught_errors.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../notifications/message_notification_action.dart';
import 'call_notification_service.dart';

final headlessMessageActionProvider =
    NotifierProvider<HeadlessMessageActionNotifier, void>(
      HeadlessMessageActionNotifier.new,
    );

const _rememberedActions = 32;

class HeadlessMessageActionNotifier extends Notifier<void> {
  final _performed = <String, Future<void>>{};

  @override
  void build() {
    final sub = CallNotificationService.instance.onMessageAction.listen(
      _handle,
    );
    ref.onDispose(sub.cancel);
  }

  Future<void> _handle(HandedMessageAction handed) async {
    try {
      final txid = handed.txid;
      if (txid == null) return await _perform(handed);
      final performing = _performed[txid] ??= _perform(handed);
      if (_performed.length > _rememberedActions) {
        _performed.remove(_performed.keys.first);
      }
      await performing;
    } finally {
      handed.finished();
    }
  }

  Future<void> _perform(HandedMessageAction handed) async {
    final action = handed.action;
    final room = ref.read(matrixClientProvider).getRoomById(action.roomId);
    try {
      if (room == null) return;
      await performMessageNotificationAction(room, action, txid: handed.txid);
    } catch (e, s) {
      reportCaught('message action ${action.kind.name}', e, s);
    }
  }
}
