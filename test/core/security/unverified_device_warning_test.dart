import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/security/unverified_device_warning.dart';

import '../../helpers/fake_matrix.dart';

void main() {
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

    test('nothing new is no warning', () {
      expect(
        unvouchedNewDeviceIds(
          hasIdentity: false,
          knownDeviceIds: {'AAA', 'BBB'},
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

  group('unvouchedDeviceWarningText', () {
    test('names the person and says what to do', () {
      final text = unvouchedDeviceWarningText('Bob');

      expect(text.title, contains('Bob'));
      expect(text.body, contains('read what you send'));
      expect(text.body, contains('check with them'));
    });
  });

  group('peopleWhoseDevicesWeWatch', () {
    void join(Room room, String id) =>
        room.setState(User(id, membership: 'join', room: room));

    test('watches private-room members, skips public rooms and self', () {
      final client = buildTestClient(userId: '@me:example.org');
      final private = buildTestRoom(client, id: '!private:example.org');
      join(private, '@me:example.org');
      join(private, '@alice:example.org');
      final public = buildTestRoom(client, id: '!public:example.org');
      public.setState(
        buildTestEvent(
          public,
          eventId: r'$join',
          senderId: '@me:example.org',
          type: EventTypes.RoomJoinRules,
          stateKey: '',
          content: {'join_rule': 'public'},
        ),
      );
      join(public, '@me:example.org');
      join(public, '@stranger:example.org');
      client.rooms.addAll([private, public]);

      expect(peopleWhoseDevicesWeWatch(client), {'@alice:example.org'});
    });
  });
}
