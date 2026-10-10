import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/chat/presentation/sender_device_tile.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_matrix.dart';

const _bob = '@bob:example.org';

class _ApprovedKeys extends DeviceKeys {
  _ApprovedKeys(Client client, String userId, String deviceId)
    : super.fromJson(testDeviceKeysJson(userId, deviceId), client);

  @override
  bool get signed => true;
}

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  Event messageFrom(String sender, {String? senderKey}) => Event(
    eventId: r'$m',
    type: EventTypes.Message,
    senderId: sender,
    originServerTs: DateTime(2026, 9, 27),
    content: {'msgtype': 'm.text', 'body': 'hi'},
    room: room,
    originalSource: MatrixEvent(
      eventId: r'$m',
      type: EventTypes.Encrypted,
      senderId: sender,
      originServerTs: DateTime(2026, 9, 27),
      content: {'algorithm': 'm.megolm.v1.aes-sha2', 'sender_key': ?senderKey},
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    Event event, {
    UserTrustState trust = UserTrustState.confirmedWithPendingDevice,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [userTrustProvider.overrideWith((ref, _) => trust)],
      child: MaterialApp(
        home: Scaffold(body: SenderDeviceTile(event: event)),
      ),
    ),
  );

  Finder tile() => find.byType(ListTile);

  testWidgets('a confirmed person writing from an unapproved device is '
      'told apart, with nothing for you to do', (tester) async {
    setTestDevices(client, _bob, {'NEWPHONE': null});
    await pump(tester, messageFrom(_bob, senderKey: 'curve-NEWPHONE'));

    expect(
      find.text('Sent from a device @bob has not approved yet'),
      findsOneWidget,
    );
    expect(find.textContaining('nothing for you to do'), findsOneWidget);
  });

  testWidgets('an approved device says nothing', (tester) async {
    setTestDevices(client, _bob, {}).deviceKeys['PHONE'] = _ApprovedKeys(
      client,
      _bob,
      'PHONE',
    );
    await pump(tester, messageFrom(_bob, senderKey: 'curve-PHONE'));

    expect(tile(), findsNothing);
  });

  testWidgets('your own messages say nothing', (tester) async {
    await pump(tester, messageFrom('@me:example.org', senderKey: 'curve-X'));

    expect(tile(), findsNothing);
  });

  for (final trust in [
    UserTrustState.confirmed,
    UserTrustState.unconfirmed,
    UserTrustState.identityChanged,
  ]) {
    testWidgets('a ${trust.name} sender says nothing', (tester) async {
      setTestDevices(client, _bob, {'NEWPHONE': null});
      await pump(
        tester,
        messageFrom(_bob, senderKey: 'curve-NEWPHONE'),
        trust: trust,
      );

      expect(tile(), findsNothing);
    });
  }

  testWidgets('an unencrypted message says nothing', (tester) async {
    await pump(tester, messageFrom(_bob));

    expect(tile(), findsNothing);
  });

  testWidgets('an unknown device says nothing', (tester) async {
    setTestDevices(client, _bob, {'PHONE': null});
    await pump(tester, messageFrom(_bob, senderKey: 'curve-ELSEWHERE'));

    expect(tile(), findsNothing);
  });

  testWidgets("someone else's device key says nothing", (tester) async {
    setTestDevices(client, '@mallory:example.org', {'EVIL': null});
    await pump(tester, messageFrom(_bob, senderKey: 'curve-EVIL'));

    expect(tile(), findsNothing);
  });
}
