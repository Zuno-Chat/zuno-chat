import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/olm_sender.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;

  setUp(() {
    client = buildTestClient(userId: '@me:x', deviceId: 'MINE');
    setSelfSignedTestDevices(client, '@alex:x', ['PHONE']);
    setSelfSignedTestDevices(client, '@bea:x', ['TABLET']);
  });

  ToDeviceEvent fromAlex({String? senderKey}) => ToDeviceEvent(
    sender: '@alex:x',
    type: 'im.zuno.test',
    content: const {},
    encryptedContent: senderKey == null
        ? null
        : {
            'sender_key': senderKey,
            'algorithm': 'm.olm.v1.curve25519-aes-sha2',
          },
  );

  test('names the known device whose Olm key sent it', () {
    final device = olmSenderDevice(client, fromAlex(senderKey: 'curve-PHONE'));

    expect(device?.userId, '@alex:x');
    expect(device?.deviceId, 'PHONE');
  });

  test('a plaintext to-device message has no verified sender', () {
    expect(olmSenderDevice(client, fromAlex()), isNull);
  });

  test('an unknown Olm key has no verified sender', () {
    expect(olmSenderDevice(client, fromAlex(senderKey: 'curve-NEW')), isNull);
  });

  test('a key of another user\'s device does not vouch for the sender', () {
    expect(
      olmSenderDevice(client, fromAlex(senderKey: 'curve-TABLET')),
      isNull,
    );
  });

  test('a copy of the key under another user cannot shadow the sender', () {
    client.userDeviceKeys.remove('@alex:x');
    setSelfSignedTestDevices(client, '@mallory:x', ['PHONE']);
    setSelfSignedTestDevices(client, '@alex:x', ['PHONE']);

    final device = olmSenderDevice(client, fromAlex(senderKey: 'curve-PHONE'));

    expect(device?.userId, '@alex:x');
  });

  test('a blocked device has no verified sender', () {
    client.userDeviceKeys['@alex:x']!.deviceKeys['PHONE']!.blocked = true;

    expect(olmSenderDevice(client, fromAlex(senderKey: 'curve-PHONE')), isNull);
  });
}
