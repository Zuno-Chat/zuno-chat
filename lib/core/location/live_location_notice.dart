import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import '../matrix/room_title.dart';
import 'live_location_capture.dart';

LiveLocationNotice liveLocationNotice(
  AppLocalizations l10n,
  List<({Room room, DateTime endsAt})> shares, {
  bool namesChats = true,
}) {
  final endsAt = shares
      .map((entry) => entry.endsAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final title = l10n.locationNoticeTitle;
  if (shares case [final only] when namesChats) {
    final name = roomTitle(only.room, l10n);
    return LiveLocationNotice(
      title: title,
      text: only.room.isDirectChat
          ? l10n.locationNoticeWith(name)
          : l10n.locationNoticeIn(name),
      endsAt: endsAt,
      roomId: only.room.id,
    );
  }
  final chats = shares.where((entry) => entry.room.isDirectChat).length;
  final rooms = shares.length - chats;
  return LiveLocationNotice(
    title: title,
    text: switch ((chats, rooms)) {
      (_, 0) => l10n.locationNoticeChats(chats),
      (0, _) => l10n.locationNoticeRooms(rooms),
      _ => l10n.locationNoticeChatsAndRooms(chats, rooms),
    },
    endsAt: endsAt,
    roomId: shares.singleOrNull?.room.id,
  );
}
