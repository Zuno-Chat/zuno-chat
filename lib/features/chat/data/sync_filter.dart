import 'package:matrix/matrix.dart';

bool syncTouchesRoom(SyncUpdate update, String roomId) {
  final rooms = update.rooms;
  if (rooms == null) return false;
  return (rooms.join?.containsKey(roomId) ?? false) ||
      (rooms.invite?.containsKey(roomId) ?? false) ||
      (rooms.leave?.containsKey(roomId) ?? false);
}
