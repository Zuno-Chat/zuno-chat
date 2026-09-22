import 'package:matrix/matrix.dart';

Future<Room?> awaitRoom(
  Client client,
  String roomId, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  var room = client.getRoomById(roomId);
  var waited = Duration.zero;
  while (room == null && waited < timeout) {
    await Future<void>.delayed(interval);
    waited += interval;
    room = client.getRoomById(roomId);
  }
  return room;
}
