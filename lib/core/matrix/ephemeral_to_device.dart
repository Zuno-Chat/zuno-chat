import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import '../location/live_location_protocol.dart';
import 'database_compaction.dart';

const _ephemeralTxnPrefix = 'zuno-ephemeral-';

const ephemeralToDeviceTypes = {
  liveLocationPositionType,
  liveLocationWatchType,
};

Future<void> sendEphemeralToDevice(
  Client client,
  List<DeviceKeys> devices,
  String type,
  Map<String, Object?> content,
) {
  assert(ephemeralToDeviceTypes.contains(type));
  return client.sendToDeviceEncrypted(
    List.of(devices),
    type,
    content,
    messageId: '$_ephemeralTxnPrefix${client.generateUniqueTransactionId()}',
  );
}

bool _isEphemeralPayload(String lastSentMessage) {
  try {
    final decoded = jsonDecode(lastSentMessage);
    return decoded is Map && ephemeralToDeviceTypes.contains(decoded['type']);
  } on FormatException {
    return false;
  }
}

mixin EphemeralToDeviceStorage on MatrixSdkDatabase {
  @override
  Future<void> setLastSentMessageUserDeviceKey(
    String lastSentMessage,
    String userId,
    String deviceId,
  ) async {
    if (_isEphemeralPayload(lastSentMessage)) return;
    await super.setLastSentMessageUserDeviceKey(
      lastSentMessage,
      userId,
      deviceId,
    );
  }

  @override
  Future<int> insertIntoToDeviceQueue(
    String type,
    String txnId,
    String content,
  ) async {
    if (txnId.startsWith(_ephemeralTxnPrefix)) return 0;
    return super.insertIntoToDeviceQueue(type, txnId, content);
  }
}

class ZunoDatabase extends MatrixSdkDatabase
    with EphemeralToDeviceStorage, CompactsAfterCacheClear {
  ZunoDatabase(super.name, {super.database}) : super.buildWithoutOpen();
}

Future<ZunoDatabase> openZunoDatabase(sqflite.Database database) async {
  final opened = ZunoDatabase('zuno', database: database);
  await opened.open();
  return opened;
}
