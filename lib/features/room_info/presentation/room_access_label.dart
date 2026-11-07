import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/rooms/communities.dart';
import '../../../core/matrix/rooms/room_access.dart';
import '../../../core/matrix/rooms/room_title.dart';
import 'room_header.dart';

class RoomAccessLabel extends StatelessWidget {
  final RoomAccess access;
  final String? community;
  final double iconSize;

  const RoomAccessLabel({
    required this.access,
    this.community,
    this.iconSize = 16,
    super.key,
  });

  factory RoomAccessLabel.of(
    Room room,
    AppLocalizations l10n, {
    double iconSize = 16,
    Key? key,
  }) => RoomAccessLabel(
    access: roomAccessOf(room),
    community: _communityName(room.client, allowedRoomIdsOf(room), l10n),
    iconSize: iconSize,
    key: key,
  );

  factory RoomAccessLabel.listed(
    SpaceRoomsChunk$2 room,
    Client client,
    AppLocalizations l10n, {
    Key? key,
  }) => RoomAccessLabel(
    access: listedRoomAccess(room.joinRule),
    community: _communityName(client, room.allowedRoomIds ?? const [], l10n),
    key: key,
  );

  @override
  Widget build(BuildContext context) => RoomDetail(
    access == RoomAccess.community
        ? community ?? access.label(context.l10n)
        : access.label(context.l10n),
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
