import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/mxc_avatar.dart';

class RoomKindAvatar extends StatelessWidget {
  final Client client;
  final Uri? avatarUrl;
  final String fallbackText;
  final bool isDirect;
  final double radius;
  final String? toneSeed;

  const RoomKindAvatar({
    required this.client,
    required this.avatarUrl,
    required this.fallbackText,
    required this.isDirect,
    this.radius = 20,
    this.toneSeed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Container(
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
          ),
        ],
      ),
    );
  }
}
