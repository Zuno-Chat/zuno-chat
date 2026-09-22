import 'package:matrix/matrix.dart';

import '../matrix/room_access.dart';

Set<String> unvouchedNewDeviceIds({
  required bool hasIdentity,
  required Set<String>? knownDeviceIds,
  required Set<String> currentDeviceIds,
}) {
  if (hasIdentity || knownDeviceIds == null) return const {};
  return currentDeviceIds.difference(knownDeviceIds);
}

({String title, String body}) unvouchedDeviceWarningText(String name) => (
  title: '$name signed in on a new device',
  body:
      'Their account has not been set up to vouch for its own devices, so this '
      'one can read what you send from now on. If you were not expecting it, '
      'check with them before sending anything sensitive.',
);

Set<String> peopleWhoseDevicesWeWatch(Client client) {
  final ownId = client.userID;
  return {
    for (final room in client.rooms)
      if (room.membership == Membership.join &&
          roomAccessOf(room) == RoomAccess.private)
        for (final user in room.getParticipants([Membership.join]))
          if (user.id != ownId) user.id,
  };
}
