import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/mxc_avatar.dart';

typedef CommunityMark = ({Uri? avatarUrl, String name, String toneSeed});

class RoomKindAvatar extends StatelessWidget {
  final Client client;
  final Uri? avatarUrl;
  final String fallbackText;
  final bool isDirect;
  final bool community;
  final CommunityMark? inCommunity;
  final double radius;
  final String toneSeed;

  const RoomKindAvatar({
    required this.client,
    required this.avatarUrl,
    required this.fallbackText,
    required this.isDirect,
    required this.toneSeed,
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
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MxcAvatar(
            client: client,
            avatarUrl: avatarUrl,
            fallbackText: fallbackText,
            radius: radius,
            toneSeed: toneSeed,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: switch (inCommunity) {
              final mark? when !isDirect => Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: colors.surface,
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
              _ => Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDirect ? Icons.person : Icons.groups,
                  size: 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

const _markRadius = 9.0;
