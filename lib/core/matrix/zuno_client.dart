import 'package:matrix/matrix.dart';

import '../push/send_keep_awake.dart';
import 'client_lease.dart';

class ZunoClient extends Client {
  ZunoClient(
    super.clientName, {
    required super.database,
    super.httpClient,
    super.verificationMethods,
    super.roomPreviewLastEvents,
    super.nativeImplementations,
    super.onSoftLogout,
    this.appClient = true,
    this.lease,
    this.keepAwake,
  });

  final bool appClient;
  final ClientLease? lease;
  final SendKeepAwake? keepAwake;

  bool _restoringSession = false;

  Future<void> restoreSession() async {
    _restoringSession = true;
    try {
      await init(waitForFirstSync: false);
    } finally {
      _restoringSession = false;
    }
  }

  @override
  Future<void> clear({
    SessionClearReason reason = SessionClearReason.unspecified,
  }) async {
    if (!appClient) {
      Logs().w('A background client kept the shared store ($reason)');
      return;
    }
    if (_restoringSession && reason == SessionClearReason.initFailed) return;
    await super.clear(reason: reason);
  }

  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> deviceKeys,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) {
    Future<void> send() => super.sendToDeviceEncrypted(
      deviceKeys,
      eventType,
      message,
      messageId: messageId,
      onlyVerified: onlyVerified,
    );
    return keepAwake?.hold(send) ?? send();
  }

  @override
  Future<String> sendMessage(
    String roomId,
    String eventType,
    String txnId,
    Map<String, Object?> body,
  ) {
    Future<String> send() => super.sendMessage(roomId, eventType, txnId, body);
    return keepAwake?.hold(send) ?? send();
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    try {
      await super.dispose(closeDatabase: closeDatabase);
    } finally {
      await lease?.release();
    }
  }
}
