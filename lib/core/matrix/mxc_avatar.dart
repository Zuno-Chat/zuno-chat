import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../ui/zuno_colors.dart';
import 'mxc_avatar_image.dart';

class MxcAvatar extends StatelessWidget {
  final Client client;
  final Uri? avatarUrl;
  final String fallbackText;
  final double radius;
  final String? toneSeed;

  const MxcAvatar({
    required this.client,
    required this.avatarUrl,
    required this.fallbackText,
    this.radius = 20,
    this.toneSeed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final initial = CircleAvatar(
      radius: radius,
      backgroundColor: avatarToneFor(toneSeed ?? fallbackText),
      foregroundColor: zunoInk,
      child: Text(
        _initial(fallbackText),
        style: TextStyle(
          fontSize: radius * 0.76,
          fontWeight: FontWeight.w500,
          height: 1,
        ),
      ),
    );
    final avatarUrl = this.avatarUrl;
    if (avatarUrl == null) return initial;

    return SizedBox.square(
      dimension: diameter,
      child: ClipOval(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Image(
            image: MxcAvatarImage(
              client: client,
              mxc: avatarUrl,
              bucket: AvatarBucket.forDiameter(diameter),
            ),
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                frame == null ? initial : child,
            errorBuilder: (context, error, stackTrace) => initial,
          ),
        ),
      ),
    );
  }
}

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
