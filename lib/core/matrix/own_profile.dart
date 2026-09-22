import 'package:matrix/matrix.dart';

import 'matrix_ids.dart';

typedef OwnProfile = ({String name, Uri? avatar});

Room? roomWithOwnMember(Client client) {
  final userId = client.userID;
  if (userId == null) return null;
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (room.getState(EventTypes.RoomMember, userId) != null) return room;
  }
  return null;
}

OwnProfile ownProfileFromMemory(Client client) {
  final userId = client.userID;
  if (userId == null) return (name: '', avatar: null);
  final room = roomWithOwnMember(client);
  if (room == null) {
    return (name: withoutServer(userId).replaceFirst('@', ''), avatar: null);
  }
  final user = room.unsafeGetUserFromMemoryOrFallback(userId);
  return (name: user.calcDisplayname(), avatar: user.avatarUrl);
}

Future<OwnProfile?> ownProfileFromStore(Client client) async {
  final userId = client.userID;
  if (userId == null) return null;
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    final user = await room.requestUser(
      userId,
      ignoreErrors: true,
      requestState: false,
      requestProfile: false,
    );
    if (user != null) {
      return (name: user.calcDisplayname(), avatar: user.avatarUrl);
    }
  }
  return null;
}
