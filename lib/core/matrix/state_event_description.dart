import 'package:matrix/matrix.dart';

String? describeStateEvent(Event event) {
  final sender = event.senderFromMemoryOrFallback.calcDisplayname();
  final stateKey = event.stateKey ?? '';

  switch (event.type) {
    case EventTypes.RoomMember:
      final target = event.room
          .unsafeGetUserFromMemoryOrFallback(stateKey)
          .calcDisplayname();
      return switch (event.content.tryGet<String>('membership')) {
        'join' => '$target joined',
        'leave' =>
          stateKey == event.senderId
              ? '$target left'
              : '$sender removed $target',
        'invite' => '$sender invited $target',
        'ban' => '$sender banned $target',
        'knock' => '$target requested to join',
        _ => "$sender updated $target's membership",
      };
    case EventTypes.RoomName:
      final name = event.content.tryGet<String>('name');
      return (name == null || name.isEmpty)
          ? '$sender removed the room name'
          : '$sender changed the room name to "$name"';
    case EventTypes.RoomTopic:
      final topic = event.content.tryGet<String>('topic');
      return (topic == null || topic.isEmpty)
          ? '$sender removed the room topic'
          : '$sender changed the topic to "$topic"';
    case EventTypes.RoomAvatar:
      return '$sender changed the room photo';
    case EventTypes.RoomCreate:
      return '$sender created the room';
    case EventTypes.RoomPowerLevels:
      return '$sender changed the room permissions';
    case EventTypes.RoomJoinRules:
      return '$sender changed who can join the room';
    case EventTypes.RoomCanonicalAlias:
      return '$sender changed the room address';
    case EventTypes.HistoryVisibility:
      return '$sender changed who can read the room history';
    case EventTypes.GuestAccess:
      return '$sender changed guest access';
    case EventTypes.Encryption:
      return '$sender turned on encryption';
    case EventTypes.RoomTombstone:
      return '$sender upgraded the room';
    default:
      return null;
  }
}
