import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/matrix/ephemeral_to_device.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_matrix.dart';

class _RecordingDatabase extends MatrixSdkDatabase {
  _RecordingDatabase() : super.buildWithoutOpen('test');

  final lastSent = <String>[];
  final queued = <String>[];

  @override
  Future<void> setLastSentMessageUserDeviceKey(
    String lastSentMessage,
    String userId,
    String deviceId,
  ) async => lastSent.add(lastSentMessage);

  @override
  Future<int> insertIntoToDeviceQueue(
    String type,
    String txnId,
    String content,
  ) async {
    queued.add(txnId);
    return queued.length;
  }
}

class _PolicyDatabase extends _RecordingDatabase
    with EphemeralToDeviceStorage {}

class _SendingClient extends Client {
  _SendingClient() : super('test', database: FakeDatabaseApi());

  final txnIds = <String?>[];

  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> deviceKeys,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) async => txnIds.add(messageId);
}

void main() {
  late _PolicyDatabase database;

  setUp(() => database = _PolicyDatabase());

  String payload(String type) => jsonEncode({
    'type': type,
    'content': {'k': 'v'},
  });

  test('a position or watch is never kept for replay', () async {
    await database.setLastSentMessageUserDeviceKey(
      payload(liveLocationPositionType),
      '@a:x',
      'D',
    );
    await database.setLastSentMessageUserDeviceKey(
      payload(liveLocationWatchType),
      '@a:x',
      'D',
    );

    expect(database.lastSent, isEmpty);
  });

  test('room keys and other messages are still kept for replay', () async {
    await database.setLastSentMessageUserDeviceKey(
      payload(EventTypes.RoomKey),
      '@a:x',
      'D',
    );
    await database.setLastSentMessageUserDeviceKey('not json', '@a:x', 'D');

    expect(database.lastSent, hasLength(2));
  });

  test('a failed ephemeral send is never queued for a later replay', () async {
    final client = _SendingClient();
    await sendEphemeralToDevice(
      client,
      [testDeviceKeys(client, '@a:x', 'D')],
      liveLocationPositionType,
      const {'k': 'v'},
    );
    final ephemeralTxn = client.txnIds.single!;

    await database.insertIntoToDeviceQueue(
      EventTypes.Encrypted,
      ephemeralTxn,
      '{}',
    );
    await database.insertIntoToDeviceQueue(EventTypes.Encrypted, 'm1.2', '{}');

    expect(database.queued, ['m1.2']);
  });

  test('ephemeral sends carry a fresh transaction id each time', () async {
    final client = _SendingClient();
    final devices = [testDeviceKeys(client, '@a:x', 'D')];

    await sendEphemeralToDevice(
      client,
      devices,
      liveLocationWatchType,
      const {},
    );
    await sendEphemeralToDevice(
      client,
      devices,
      liveLocationWatchType,
      const {},
    );

    expect(client.txnIds.toSet(), hasLength(2));
  });
}
