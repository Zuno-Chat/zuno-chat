import 'package:matrix/matrix.dart';

Future<User> resolveRoomUser(
  Room room,
  String userId, {
  bool allowNetwork = false,
}) async {
  try {
    final user = await room.requestUser(
      userId,
      ignoreErrors: true,
      requestState: allowNetwork,
      requestProfile: allowNetwork,
    );
    if (user != null) return user;
  } catch (_) {}
  return room.unsafeGetUserFromMemoryOrFallback(userId);
}
