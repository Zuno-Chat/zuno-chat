import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';

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
  } catch (e, s) {
    reportCaught('resolve a room user', e, s);
  }
  return room.unsafeGetUserFromMemoryOrFallback(userId);
}
