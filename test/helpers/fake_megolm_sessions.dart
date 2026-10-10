import 'package:matrix/encryption/utils/stored_inbound_group_session.dart';
import 'package:zuno/core/push/read_model/session_exporter.dart';

import 'fake_matrix.dart';

class SessionStoreFakeDatabaseApi extends FakeDatabaseApi {
  final sessions = <String, StoredInboundGroupSession>{};
  bool failWrites = false;
  bool failReads = false;
  void Function()? duringRead;

  StoredInboundGroupSession put(
    String roomId,
    String sessionId, {
    String indexes = '{}',
    String senderKey = 'curve-a',
  }) => sessions[sessionId] = StoredInboundGroupSession(
    roomId: roomId,
    sessionId: sessionId,
    pickle: 'pickle-$sessionId',
    content: '{}',
    indexes: indexes,
    allowedAtIndex: '{}',
    senderKey: senderKey,
    senderClaimedKeys: '{}',
  );

  @override
  Future<StoredInboundGroupSession?> getInboundGroupSession(
    String roomId,
    String sessionId,
  ) async {
    if (failReads) throw StateError('unreadable');
    duringRead?.call();
    return sessions[sessionId];
  }

  @override
  Future<List<StoredInboundGroupSession>> getAllInboundGroupSessions() async =>
      sessions.values.toList();

  @override
  Future<void> storeInboundGroupSession(
    String roomId,
    String sessionId,
    String pickle,
    String content,
    String indexes,
    String allowedAtIndex,
    String senderKey,
    String senderClaimedKey,
  ) async {
    if (failWrites) throw StateError('disk full');
    put(roomId, sessionId, indexes: indexes, senderKey: senderKey);
  }

  @override
  Future<void> updateInboundGroupSessionIndexes(
    String indexes,
    String roomId,
    String sessionId,
  ) async {
    if (failWrites) throw StateError('disk full');
    put(roomId, sessionId, indexes: indexes);
  }
}

class FakeMegolmTrimmer implements MegolmTrimmer {
  final calls = <String>[];

  @override
  TrimmedSession? trim({
    required String pickle,
    required String userId,
    required int fromIndex,
  }) {
    calls.add('$pickle@$fromIndex');
    if (pickle == 'pickle-broken') return null;
    return TrimmedSession(pickle: 'trimmed-$pickle', firstIndex: fromIndex);
  }
}
