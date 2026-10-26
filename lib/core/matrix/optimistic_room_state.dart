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

void applyOptimisticMembership(
  Room room,
  String userId,
  Membership membership,
) => applyOptimisticRoomState(room, EventTypes.RoomMember, {
  ...?room.getState(EventTypes.RoomMember, userId)?.content,
  'membership': membership.name,
}, stateKey: userId);
