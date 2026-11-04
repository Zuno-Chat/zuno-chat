import 'package:matrix/matrix.dart';

Future<Room?> joinAndAwaitRoom(
  Client client,
  String roomId, {
  List<String>? via,
}) async {
  await client.joinRoom(roomId, via: via);
  final room = client.getRoomById(roomId);
  if (room != null && room.membership == Membership.join) return room;
  await client.waitForRoomInSync(roomId, join: true);
  return client.getRoomById(roomId);
}
