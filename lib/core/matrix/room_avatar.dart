import 'package:matrix/matrix.dart';

import 'optimistic_room_state.dart';

Future<void> setRoomAvatar(Room room, MatrixFile? file) async {
  final client = room.client;
  final url = file == null
      ? null
      : (await client.uploadContent(
          file.bytes,
          filename: file.name,
        )).toString();
  final content = <String, Object?>{'url': ?url};
  await client.setRoomStateWithKey(room.id, EventTypes.RoomAvatar, '', content);
  applyOptimisticRoomState(room, EventTypes.RoomAvatar, content);
}
