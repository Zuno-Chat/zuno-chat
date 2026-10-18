import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../l10n/l10n.dart';
import '../matrix/mxc_avatar.dart';
import '../matrix/room_title.dart';
import 'matrixrtc/incoming_call.dart';

typedef RingIdentity = ({
  String name,
  String? caller,
  Uri? avatarUrl,
  String toneSeed,
});

Future<void> loadRingIdentity(
  IncomingCall call, {
  bool allowNetwork = false,
}) async {
  final room = call.room;
  final fetch = allowNetwork && room.isDirectChat;
  await Future.wait([
    runBestEffort(
      () => loadRoomNameMembers(room),
      label: 'load the members naming a ringing chat',
    ),
    runBestEffort(
      () => room.requestUser(
        call.callerId,
        ignoreErrors: true,
        requestState: fetch,
        requestProfile: fetch,
      ),
      label: 'load a ringing call\'s caller',
    ),
  ]);
}

RingIdentity ringIdentity(IncomingCall call, AppLocalizations l10n) {
  final room = call.room;
  final caller = room
      .getState(EventTypes.RoomMember, call.callerId)
      ?.asUser(room);
  if (!room.isDirectChat) {
    return (
      name: roomTitle(room, l10n),
      caller: caller?.calcDisplayname(),
      avatarUrl: room.avatar,
      toneSeed: roomToneSeed(room),
    );
  }
  return (
    name: (caller ?? User(call.callerId, room: room)).calcDisplayname(),
    caller: null,
    avatarUrl: caller?.avatarUrl,
    toneSeed: call.callerId,
  );
}
