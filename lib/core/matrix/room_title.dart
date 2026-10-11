import 'package:matrix/matrix.dart';

String roomTitle(Room room) {
  final partner = room.directChatMatrixID;
  if (room.isAbandonedDMRoom && partner != null) {
    return room.unsafeGetUserFromMemoryOrFallback(partner).calcDisplayname();
  }
  final name = room.getLocalizedDisplayname();
  final trimmed = name.trim();
  return trimmed.isEmpty || trimmed == 'Group with' ? 'Empty chat' : name;
}

Future<void> loadRoomNameMembers(Room room) async {
  final named = room.name.isNotEmpty || room.canonicalAlias.isNotEmpty;
  final ids = {if (!named) ...?room.summary.mHeroes, ?room.directChatMatrixID}
    ..remove(room.client.userID);
  await Future.wait([
    for (final id in ids)
      if (room.getState(EventTypes.RoomMember, id) == null)
        room.requestUser(
          id,
          ignoreErrors: true,
          requestState: false,
          requestProfile: false,
        ),
  ]);
}
