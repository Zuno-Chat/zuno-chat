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
