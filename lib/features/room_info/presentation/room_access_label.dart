import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/rooms/communities.dart';
import '../../../core/matrix/rooms/room_access.dart';
import '../../../core/matrix/rooms/room_title.dart';
import 'room_header.dart';

class RoomAccessLabel extends StatelessWidget {
  final RoomAccess access;
  final String text;
  final double iconSize;

  RoomAccessLabel._({
    required this.access,
    required String? community,
    required bool inCommunity,
    required AppLocalizations l10n,
    this.iconSize = 16,
    super.key,
  }) : text = switch ((access, community)) {
         (RoomAccess.community, final String name) => name,
         _ => access.label(l10n, inCommunity: inCommunity),
       };

  factory RoomAccessLabel.of(
    Room room,
    AppLocalizations l10n, {
    double iconSize = 16,
    Key? key,
  }) => RoomAccessLabel._(
    access: roomAccessOf(room),
    community: _communityName(room.client, allowedRoomIdsOf(room), l10n),
    inCommunity: isCommunityRoom(room),
    l10n: l10n,
    iconSize: iconSize,
    key: key,
  );

  factory RoomAccessLabel.listed(
    SpaceRoomsChunk$2 room,
    Client client,
    AppLocalizations l10n, {
    Key? key,
  }) => RoomAccessLabel._(
    access: listedRoomAccess(room.joinRule),
    community: _communityName(client, room.allowedRoomIds ?? const [], l10n),
    inCommunity: true,
    l10n: l10n,
    key: key,
  );

  @override
  Widget build(BuildContext context) => RoomDetail(
    text,
    icon: switch (access) {
      RoomAccess.public => Icons.public,
      RoomAccess.community => Icons.workspaces_outlined,
      RoomAccess.askToJoin => Icons.front_hand_outlined,
      RoomAccess.private => Icons.public_off,
    },
    iconSize: iconSize,
  );
}

String? _communityName(
  Client client,
  Iterable<String> allowed,
  AppLocalizations l10n,
) {
  for (final id in allowed) {
    if (client.getRoomById(id) case final community?
        when isJoinedCommunity(community)) {
      return roomTitle(community, l10n);
    }
  }
  return null;
}
