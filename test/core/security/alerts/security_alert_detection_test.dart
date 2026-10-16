import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/alerts/security_alert.dart';
import 'package:zuno/core/security/alerts/security_alert_detection.dart';
import 'package:zuno/core/security/user_trust.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _alice = '@alice:example.org';
const _bob = '@bob:example.org';

void _join(Room room, String id, {String membership = 'join'}) =>
    room.setState(User(id, membership: membership, room: room));

void _setJoinRule(Room room, String joinRule) => room.setState(
  buildTestEvent(
    room,
    eventId: r'$join',
    senderId: _me,
    type: EventTypes.RoomJoinRules,
    stateKey: '',
    content: {'join_rule': joinRule},
  ),
);

void main() {
  group('newSignInAlerts', () {
    test('a device that was not there before is an alert', () {
      final alerts = newSignInAlerts(
        knownDeviceIds: {'AAA'},
        currentDevices: {'AAA': 'Old phone', 'BBB': 'New phone'},
        ownDeviceId: 'AAA',
      );

      expect(alerts, [
        const NewSignInAlert(deviceId: 'BBB', displayName: 'New phone'),
      ]);
    });

    test('nothing new is no alert', () {
      expect(
        newSignInAlerts(
          knownDeviceIds: {'AAA', 'BBB'},
          currentDevices: {'AAA': null, 'BBB': null},
          ownDeviceId: 'AAA',
        ),
        isEmpty,
      );
    });

    test('the very first look alerts about nothing at all', () {
      expect(
        newSignInAlerts(
          knownDeviceIds: null,
          currentDevices: {'AAA': null, 'BBB': null, 'CCC': null},
          ownDeviceId: 'AAA',
        ),
        isEmpty,
      );
    });

    test('a recorded-but-empty set is not the same as never looked', () {
      expect(
        newSignInAlerts(
          knownDeviceIds: const {},
          currentDevices: {'BBB': null},
          ownDeviceId: 'AAA',
        ),
        hasLength(1),
      );
    });

    test('this device is never an alert about itself', () {
      expect(
        newSignInAlerts(
          knownDeviceIds: const {},
          currentDevices: {'AAA': 'This device'},
          ownDeviceId: 'AAA',
        ),
        isEmpty,
      );
    });

    test('several at once are reported one by one, not as a count', () {
      final alerts = newSignInAlerts(
        knownDeviceIds: {'AAA'},
        currentDevices: {'AAA': null, 'BBB': null, 'CCC': null},
        ownDeviceId: 'AAA',
      );

      expect(alerts.map((a) => a.deviceId), ['BBB', 'CCC']);
    });
  });

  group('newSignInText', () {
    test('names the device, and says what to do', () {
      final text = newSignInText(
        englishLocalizations,
        const NewSignInAlert(deviceId: 'BBB', displayName: 'Pixel 8a'),
      );

      expect(text.title, 'New sign-in');
      expect(text.body, contains('Pixel 8a'));
      expect(text.body, contains('sign it out'));
    });

    test('an unnamed device falls back to its ID, never to "Unknown"', () {
      expect(
        newSignInText(
          englishLocalizations,
          const NewSignInAlert(deviceId: 'BBB'),
        ).body,
        contains('BBB'),
      );
      expect(
        newSignInText(
          englishLocalizations,
          const NewSignInAlert(deviceId: 'BBB', displayName: '   '),
        ).body,
        contains('BBB'),
      );
    });
  });

  group('unvouchedNewDeviceIds', () {
    test('a new device on an account with no identity is flagged', () {
      expect(
        unvouchedNewDeviceIds(
          hasIdentity: false,
          knownDeviceIds: {'AAA'},
          currentDeviceIds: {'AAA', 'BBB'},
        ),
        {'BBB'},
      );
    });

    test('the same device on an account with an identity is not', () {
      expect(
        unvouchedNewDeviceIds(
          hasIdentity: true,
          knownDeviceIds: {'AAA'},
          currentDeviceIds: {'AAA', 'BBB'},
        ),
        isEmpty,
      );
    });

    test('meeting someone for the first time warns about nothing', () {
      expect(
        unvouchedNewDeviceIds(
          hasIdentity: false,
          knownDeviceIds: null,
          currentDeviceIds: {'AAA', 'BBB'},
        ),
        isEmpty,
      );
    });

    test('a device disappearing is not a warning', () {
      expect(
        unvouchedNewDeviceIds(
          hasIdentity: false,
          knownDeviceIds: {'AAA', 'BBB'},
          currentDeviceIds: {'AAA'},
        ),
        isEmpty,
      );
    });
  });

  group('unvouchedDeviceText', () {
    test('names the person and says what to do', () {
      final text = unvouchedDeviceText(englishLocalizations, 'Bob');

      expect(text.title, contains('Bob'));
      expect(text.body, contains('read what you send'));
      expect(text.body, contains('check with them'));
    });
  });

  group('peopleWhoseDevicesWeWatch', () {
    test('watches private-room members, skips public rooms and self', () {
      final client = buildTestClient(userId: _me);
      final private = buildTestRoom(client, id: '!private:example.org');
      _join(private, _me);
      _join(private, _alice);
      final public = buildTestRoom(client, id: '!public:example.org');
      _setJoinRule(public, 'public');
      _join(public, _me);
      _join(public, '@stranger:example.org');
      client.rooms.addAll([private, public]);

      expect(peopleWhoseDevicesWeWatch(client), {_alice});
    });

    test('watches rooms open to community members, not the community '
        'itself', () {
      final client = buildTestClient(userId: _me);
      final room = buildTestRoom(client, id: '!gear:example.org');
      _setJoinRule(room, 'restricted');
      _join(room, '@maya:example.org');
      final community = buildTestRoom(client, id: '!club:example.org');
      community.setState(
        buildTestEvent(
          community,
          eventId: r'$create',
          senderId: _me,
          type: EventTypes.RoomCreate,
          stateKey: '',
          content: {'type': 'm.space'},
        ),
      );
      _join(community, '@leo:example.org');
      client.rooms.addAll([room, community]);

      expect(peopleWhoseDevicesWeWatch(client), {'@maya:example.org'});
    });
  });

  group('recoveryResetAlerts', () {
    test('a new identity this device did not make is an alert', () {
      expect(
        recoveryResetAlerts(
          knownIdentityKey: 'OLD',
          currentIdentityKey: 'NEW',
          thisDeviceApproved: false,
        ),
        const [RecoveryResetAlert('NEW')],
      );
    });

    test('the first look and an unchanged identity are no alert', () {
      for (final known in [null, 'SAME']) {
        expect(
          recoveryResetAlerts(
            knownIdentityKey: known,
            currentIdentityKey: 'SAME',
            thisDeviceApproved: false,
          ),
          isEmpty,
        );
      }
    });

    test('a new identity this device already belongs to is no alert', () {
      expect(
        recoveryResetAlerts(
          knownIdentityKey: 'OLD',
          currentIdentityKey: 'NEW',
          thisDeviceApproved: true,
        ),
        isEmpty,
      );
    });

    test('an account without recovery is no alert', () {
      expect(
        recoveryResetAlerts(
          knownIdentityKey: 'OLD',
          currentIdentityKey: null,
          thisDeviceApproved: false,
        ),
        isEmpty,
      );
    });
  });

  group('accountSecurityAlerts', () {
    const reset = RecoveryResetAlert('NEW');
    const signIn = NewSignInAlert(deviceId: 'PIXEL');

    List<SecurityAlert> alerts({
      List<RecordedSecurityAlert> recorded = const [],
      AccountSecurityStatus? status,
      AccountSecurityStatus? dismissed,
    }) => accountSecurityAlerts(
      recorded: recorded,
      status: status,
      dismissedStatus: dismissed,
    );

    test('shows a locked device, a waiting device and a stale code', () {
      for (final status in [
        AccountSecurityStatus.deviceLocked,
        AccountSecurityStatus.deviceWaiting,
        AccountSecurityStatus.recoveryStale,
      ]) {
        expect(alerts(status: status), [AccountStatusAlert(status)]);
      }
    });

    test('leaves no recovery to its own prompt, and protected silent', () {
      for (final status in [
        AccountSecurityStatus.noRecovery,
        AccountSecurityStatus.protected,
        null,
      ]) {
        expect(alerts(status: status), isEmpty);
      }
    });

    test('a reset explains the locked device, so only the reset shows', () {
      expect(
        alerts(recorded: [reset], status: AccountSecurityStatus.deviceLocked),
        [reset],
      );
    });

    test('a new sign-in explains the waiting device, so only it shows', () {
      expect(
        alerts(recorded: [signIn], status: AccountSecurityStatus.deviceWaiting),
        [signIn],
      );
    });

    test('a dismissed status stays hidden until the status changes', () {
      expect(
        alerts(
          status: AccountSecurityStatus.recoveryStale,
          dismissed: AccountSecurityStatus.recoveryStale,
        ),
        isEmpty,
      );
      expect(
        alerts(
          status: AccountSecurityStatus.deviceLocked,
          dismissed: AccountSecurityStatus.recoveryStale,
        ),
        [const AccountStatusAlert(AccountSecurityStatus.deviceLocked)],
      );
    });

    test('person-level alerts never show here', () {
      expect(
        alerts(
          recorded: const [
            UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          ],
        ),
        isEmpty,
      );
    });
  });

  group('callDeviceUnvouched', () {
    late Client client;

    setUp(() => client = buildTestClient(userId: _me, deviceId: 'THIS'));

    bool unvouched(
      String userId,
      String deviceId, {
      List<RecordedSecurityAlert> recorded = const [],
    }) => callDeviceUnvouched(client, (
      userId: userId,
      deviceId: deviceId,
    ), recorded: recorded);

    test('a device its owner never approved is unvouched', () {
      setTestDevices(client, _alice, {'A1': null});
      testMasterKey(client, _alice);

      expect(unvouched(_alice, 'A1'), isTrue);
    });

    test('a device its owner approved is fine', () {
      setTestDevices(client, _alice, {}).deviceKeys['A1'] =
          OwnerSignedTestDeviceKeys(testDeviceKeysJson(_alice, 'A1'), client);
      testMasterKey(client, _alice);

      expect(unvouched(_alice, 'A1'), isFalse);
    });

    test('on an account that cannot approve devices, only a flagged new '
        'device is unvouched', () {
      setTestDevices(client, _alice, {'A1': null, 'A2': null});
      const recorded = [
        UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
      ];

      expect(unvouched(_alice, 'A1', recorded: recorded), isFalse);
      expect(unvouched(_alice, 'A2', recorded: recorded), isTrue);
    });

    test('a device whose keys are not loaded yet is not flagged', () {
      setTestDevices(client, _alice, {'A1': null});
      testMasterKey(client, _alice);

      expect(unvouched(_alice, 'A9'), isFalse);
      expect(unvouched(_bob, 'B1'), isFalse);
    });
  });

  group('withRaised', () {
    test('adds new alerts after the open ones', () {
      expect(
        withRaised(
          const [NewSignInAlert(deviceId: 'OLD')],
          const [NewSignInAlert(deviceId: 'NEW')],
        ),
        const [
          NewSignInAlert(deviceId: 'OLD'),
          NewSignInAlert(deviceId: 'NEW'),
        ],
      );
    });

    test('another new device of a flagged person joins their alert', () {
      expect(
        withRaised(
          const [
            UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          ],
          const [
            UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A3'}),
          ],
        ),
        const [
          UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2', 'A3'}),
        ],
      );
    });
  });

  group('securityAlertStillOpen', () {
    late Client client;

    setUp(() => client = buildTestClient(userId: _me, deviceId: 'THIS'));

    test('a new sign-in stays open while the device is there, unapproved', () {
      setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});

      expect(
        securityAlertStillOpen(const NewSignInAlert(deviceId: 'PIXEL'), client),
        isTrue,
      );
    });

    test('a new sign-in closes once that device is signed out', () {
      setTestDevices(client, _me, {'THIS': null});

      expect(
        securityAlertStillOpen(const NewSignInAlert(deviceId: 'PIXEL'), client),
        isFalse,
      );
    });

    test('a new sign-in closes once that device is approved', () {
      setTestDevices(client, _me, {'THIS': null}).deviceKeys['PIXEL'] =
          ApprovedTestDeviceKeys(testDeviceKeysJson(_me, 'PIXEL'), client);

      expect(
        securityAlertStillOpen(const NewSignInAlert(deviceId: 'PIXEL'), client),
        isFalse,
      );
    });

    test('a list the server is still refreshing closes nothing', () {
      setTestDevices(client, _me, {'THIS': null}, outdated: true);

      expect(
        securityAlertStillOpen(const NewSignInAlert(deviceId: 'PIXEL'), client),
        isTrue,
      );
    });

    test('a flagged person stays flagged while a flagged device is there', () {
      setTestDevices(client, _alice, {'A1': null, 'A2': null});

      expect(
        securityAlertStillOpen(
          const UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          client,
        ),
        isTrue,
      );
    });

    test('a flagged person clears once every flagged device is gone', () {
      setTestDevices(client, _alice, {'A1': null});

      expect(
        securityAlertStillOpen(
          const UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          client,
        ),
        isFalse,
      );
    });

    test('a flagged person clears once their account vouches for devices', () {
      setTestDevices(client, _alice, {'A1': null, 'A2': null});
      testMasterKey(client, _alice);

      expect(
        securityAlertStillOpen(
          const UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          client,
        ),
        isFalse,
      );
    });

    test(
      'a reset stays open until this device belongs to the new identity',
      () {
        setTestDevices(client, _me, {'THIS': null});
        final master = testMasterKey(client, _me);
        final alert = RecoveryResetAlert(master.ed25519Key!);
        expect(securityAlertStillOpen(alert, client), isTrue);

        client.userDeviceKeys[_me]!.deviceKeys['THIS'] =
            OwnerSignedTestDeviceKeys(testDeviceKeysJson(_me, 'THIS'), client);

        expect(securityAlertStillOpen(alert, client), isFalse);
      },
    );

    test('a reset closes once the identity changes again', () {
      setTestDevices(client, _me, {'THIS': null});
      testMasterKey(client, _me);

      expect(
        securityAlertStillOpen(const RecoveryResetAlert('OLDER'), client),
        isFalse,
      );
    });

    test('a person whose devices are no longer tracked stays flagged', () {
      expect(
        securityAlertStillOpen(
          const UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          client,
        ),
        isTrue,
      );
    });
  });

  group('roomSecurityAlerts', () {
    late Client client;
    late Room room;

    setUp(() {
      client = buildTestClient(userId: _me);
      room = buildTestRoom(client);
      _join(room, _me);
      _join(room, _alice);
      _join(room, _bob, membership: 'invite');
      _join(room, '@dave:example.org', membership: 'leave');
    });

    UserTrustState Function(String) changed(Set<String> ids) =>
        (id) => ids.contains(id)
        ? UserTrustState.identityChanged
        : UserTrustState.confirmed;

    test('names joined and invited people whose identity changed', () {
      expect(
        roomSecurityAlerts(
          room,
          recorded: const [],
          trustOf: changed({_alice, _bob, _me, '@dave:example.org'}),
        ),
        const [IdentityChangedAlert(_alice), IdentityChangedAlert(_bob)],
      );
    });

    test('shows a flagged person only where they have joined', () {
      final alerts = roomSecurityAlerts(
        room,
        recorded: const [
          UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          UnvouchedDeviceAlert(userId: _bob, deviceIds: {'B2'}),
          NewSignInAlert(deviceId: 'PIXEL'),
        ],
        trustOf: changed(const {}),
      );

      expect(alerts, const [
        UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
      ]);
    });

    test('a flagged person is not shown in a public room', () {
      _setJoinRule(room, 'public');

      expect(
        roomSecurityAlerts(
          room,
          recorded: const [
            UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
          ],
          trustOf: changed(const {}),
        ),
        isEmpty,
      );
    });

    test('identity changes come before flagged devices', () {
      final alerts = roomSecurityAlerts(
        room,
        recorded: const [
          UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
        ],
        trustOf: changed({_bob}),
      );

      expect(alerts.first, const IdentityChangedAlert(_bob));
    });
  });
}
