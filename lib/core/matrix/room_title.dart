import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import 'room_name_localizations.dart';

String roomTitle(Room room, AppLocalizations l10n) {
  final names = RoomNameLocalizations(l10n);
  final partner = room.directChatMatrixID;
  if (room.isAbandonedDMRoom && partner != null) {
    return room
        .unsafeGetUserFromMemoryOrFallback(partner)
        .calcDisplayname(i18n: names);
  }
  final name = room.getLocalizedDisplayname(names);
  return name.trim().isEmpty ? l10n.roomNameEmpty : name;
}

Future<void> loadRoomNameMembers(Room room) async {
  final named = room.name.isNotEmpty || room.canonicalAlias.isNotEmpty;
  final ids = {if (!named) ...?room.summary.mHeroes, ?room.directChatMatrixID}
    ..remove(room.client.userID);
  await Future.wait([
    for (final id in ids)
      if (room.getState(EventTypes.RoomMember, id) == null)
        room.requestUser(
          id,
          ignoreErrors: true,
          requestState: false,
          requestProfile: false,
        ),
  ]);
}
