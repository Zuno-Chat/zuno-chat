import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'fake_device_keys.dart';
import 'fake_matrix.dart';

typedef ToDeviceSend = ({
  String deviceId,
  String type,
  Map<String, dynamic> body,
});

class ToDeviceRecordingClient extends Client {
  ToDeviceRecordingClient({String userId = '@me:example.org'})
    : super('test', database: FakeDatabaseApi()) {
    setUserId(userId);
  }

  final unreachable = <String>{};
  final tries = <String>[];
  var requests = 0;
  final sent = <ToDeviceSend>[];
  Completer<void>? hold;
  bool olm = false;
  late final Encryption _olm = Encryption(client: this);

  Map<String, Map<String, dynamic>> get keysSent => {
    for (final send in sent) send.deviceId: send.body,
  };

  @override
  String? get deviceID => 'TESTDEVICE';

  @override
  bool get encryptionEnabled => olm;

  @override
  Encryption? get encryption => olm ? _olm : null;

  void openOlmSession(String deviceId) => openTestOlmSession(_olm, deviceId);

  bool _hasOlmSession(DeviceKeys device) =>
      _olm.olmManager.olmSessions[device.curve25519Key]?.isNotEmpty ?? false;

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async => '\$evt';

  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> deviceKeys,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) async {
    requests++;
    final held = hold;
    hold = null;
    for (final device in deviceKeys) {
      final deviceId = device.deviceId!;
      tries.add(deviceId);
      if (held != null) {
        await held.future;
      } else if (unreachable.contains(deviceId)) {
        throw http.ClientException('502 Bad Gateway');
      }
      if (olm && !_hasOlmSession(device)) continue;
      sent.add((deviceId: deviceId, type: eventType, body: message));
    }
  }
}
