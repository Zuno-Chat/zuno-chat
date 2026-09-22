import 'package:matrix/matrix.dart';

void applyOptimisticRoomState(
  Room room,
  String type,
  Map<String, Object?> content, {
  String stateKey = '',
}) {
  room.setState(
    StrippedStateEvent(
      type: type,
      content: content,
      senderId: room.client.userID ?? '',
      stateKey: stateKey,
    ),
  );
}
