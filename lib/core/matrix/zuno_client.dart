import 'package:matrix/matrix.dart';

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
  });

  final bool appClient;
  final ClientLease? lease;

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
  Future<void> dispose({bool closeDatabase = true}) async {
    try {
      await super.dispose(closeDatabase: closeDatabase);
    } finally {
      await lease?.release();
    }
  }
}
