import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/security/confirmed_person_mark.dart';
import '../../../core/ui/avatar_mark.dart';

typedef CommunityMark = ({Uri? avatarUrl, String name, String toneSeed});

class RoomKindAvatar extends StatelessWidget {
  final Client client;
  final Uri? avatarUrl;
  final String fallbackText;
  final String? directUserId;
  final bool community;
  final CommunityMark? inCommunity;
  final double radius;
  final String toneSeed;

  const RoomKindAvatar({
    required this.client,
    required this.avatarUrl,
    required this.fallbackText,
    required this.toneSeed,
    this.directUserId,
    this.community = false,
    this.inCommunity,
    this.radius = 20,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (community) {
      return MxcAvatar(
        client: client,
        avatarUrl: avatarUrl,
        fallbackText: fallbackText,
        radius: radius,
        toneSeed: toneSeed,
        shape: AvatarShape.roundedSquare,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return MarkedAvatar(
      avatar: MxcAvatar(
        client: client,
        avatarUrl: avatarUrl,
        fallbackText: fallbackText,
        radius: radius,
        toneSeed: toneSeed,
      ),
      mark: switch ((directUserId, inCommunity)) {
        (final userId?, _) => ConfirmedPersonMark(
          userId: userId,
          orElse: AvatarMark(
            icon: Icons.person,
            color: colors.onSurfaceVariant,
          ),
        ),
        (null, final mark?) => Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: avatarMarkRingColor(context),
            borderRadius: BorderRadius.circular(_markRadius * 0.6 + 1.5),
          ),
          child: MxcAvatar(
            client: client,
            avatarUrl: mark.avatarUrl,
            fallbackText: mark.name,
            toneSeed: mark.toneSeed,
            radius: _markRadius,
            shape: AvatarShape.roundedSquare,
          ),
        ),
        (null, null) => AvatarMark(
          icon: Icons.groups,
          color: colors.onSurfaceVariant,
        ),
      },
    );
  }
}

const _markRadius = 9.0;
