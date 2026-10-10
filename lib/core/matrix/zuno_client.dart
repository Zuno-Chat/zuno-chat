import 'package:matrix/matrix.dart';

import '../push/send_keep_awake.dart';
import 'client_lease.dart';
import 'sync_coordinator.dart';

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
  SyncCoordinator? syncCoordinator;

  bool _restoringSession = false;

  // FIXME: matrix SDK adds a sync loop per mid-request abortSync() (upstream).
  @override
  set backgroundSync(bool enabled) =>
      super.backgroundSync = enabled && syncCoordinator == null;

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
    syncCoordinator?.cancelWaitingRequest();
    await super.clear(reason: reason);
  }

  @override
  Future<void> clearCache() =>
      syncCoordinator?.whileIdle(super.clearCache) ?? super.clearCache();

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
    syncCoordinator?.dispose();
    try {
      await super.dispose(closeDatabase: closeDatabase);
    } finally {
      await lease?.release();
    }
  }
}
