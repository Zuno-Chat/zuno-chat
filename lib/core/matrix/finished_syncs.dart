import 'package:matrix/matrix.dart';

Stream<SyncStatusUpdate> finishedSyncs(Client client) => client
    .onSyncStatus
    .stream
    .where((update) => update.status == SyncStatus.finished);
