import 'package:matrix/matrix.dart';

import '../matrix/room_permission.dart';
import 'live_location_protocol.dart';

enum LiveLocationAvailability {
  unavailable,
  notAllowed,
  alreadySharing,
  available,
}

LiveLocationAvailability liveLocationAvailability(
  Room room, {
  required bool sharingHere,
}) {
  if (room.membership != Membership.join ||
      room.isSpace ||
      !room.encrypted ||
      !room.client.encryptionEnabled) {
    return LiveLocationAvailability.unavailable;
  }
  if (sharingHere) return LiveLocationAvailability.alreadySharing;
  if (!canPostInRoom(room) ||
      !room.canChangeStateEvent(liveLocationStateType)) {
    return LiveLocationAvailability.notAllowed;
  }
  return LiveLocationAvailability.available;
}
