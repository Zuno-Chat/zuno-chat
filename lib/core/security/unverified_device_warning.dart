import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import '../matrix/room_access.dart';

Set<String> unvouchedNewDeviceIds({
  required bool hasIdentity,
  required Set<String>? knownDeviceIds,
  required Set<String> currentDeviceIds,
}) {
  if (hasIdentity || knownDeviceIds == null) return const {};
  return currentDeviceIds.difference(knownDeviceIds);
}

({String title, String body}) unvouchedDeviceWarningText(
  AppLocalizations l10n,
  String name,
) => (
  title: l10n.securityUnvouchedDeviceTitle(name),
  body: l10n.securityUnvouchedDeviceBody,
);

Set<String> peopleWhoseDevicesWeWatch(Client client) {
  final ownId = client.userID;
  return {
    for (final room in client.rooms)
      if (room.membership == Membership.join &&
          !room.isSpace &&
          roomAccessOf(room) != RoomAccess.public)
        for (final user in room.getParticipants([Membership.join]))
          if (user.id != ownId) user.id,
  };
}
