import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/room_title.dart';

const notificationRoomCacheKey = 'notifications.rooms';

typedef NotificationRoomEntry = ({String id, String name, bool isDirect});

String encodeNotificationRoomCache(Iterable<NotificationRoomEntry> rooms) => [
  for (final room in rooms)
    if (room.id.isNotEmpty)
      '${room.id}\t${room.isDirect ? 'd' : 'g'}\t${_singleLine(room.name)}',
].join('\n');

String _singleLine(String name) =>
    name.replaceAll(RegExp(r'[\t\n\r]+'), ' ').trim();

Iterable<NotificationRoomEntry> notificationRoomEntriesOf(Client client) => [
  for (final room in client.rooms)
    if (room.membership == Membership.join)
      (id: room.id, name: roomTitle(room), isDirect: room.isDirectChat),
];

bool notificationRoomCacheDirty(SyncUpdate update) {
  if (update.accountData?.any((e) => e.type == 'm.direct') ?? false) {
    return true;
  }
  final rooms = update.rooms;
  if (rooms == null) return false;
  if (rooms.leave?.isNotEmpty ?? false) return true;
  for (final room in rooms.join?.values ?? const <JoinedRoomUpdate>[]) {
    if (room.state?.isNotEmpty ?? false) return true;
    final events = room.timeline?.events;
    if (events != null && events.any((e) => e.stateKey != null)) return true;
  }
  return false;
}

class NotificationRoomCacheWriter {
  String? _last;

  bool get hasWritten => _last != null;

  Future<bool> write(
    SharedPreferences prefs,
    Iterable<NotificationRoomEntry> rooms,
  ) async {
    final encoded = encodeNotificationRoomCache(rooms);
    if (encoded == _last) return false;
    await prefs.setString(notificationRoomCacheKey, encoded);
    _last = encoded;
    return true;
  }
}
