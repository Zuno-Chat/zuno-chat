import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../ui/zuno_colors.dart';
import 'mxc_avatar_image.dart';
import 'room_invite.dart';

enum AvatarShape {
  circle,
  roundedSquare;

  static AvatarShape forRoom(Room room) =>
      room.isSpace ? roundedSquare : circle;
}

String roomToneSeed(Room room) {
  if (isIncomingInvite(room)) {
    if (room.name.isNotEmpty) return room.id;
    return inviterId(room) ?? room.id;
  }
  return room.directChatMatrixID ?? room.id;
}

class MxcAvatar extends StatelessWidget {
  final Client client;
  final Uri? avatarUrl;
  final String fallbackText;
  final double radius;
  final String toneSeed;
  final AvatarShape shape;

  const MxcAvatar({
    required this.client,
    required this.avatarUrl,
    required this.fallbackText,
    required this.toneSeed,
    this.radius = 20,
    this.shape = AvatarShape.circle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final corners = BorderRadius.circular(radius * 0.6);
    final tone = avatarToneFor(toneSeed);
    final letter = Text(
      _initial(fallbackText),
      style: TextStyle(
        fontSize: radius * 0.76,
        fontWeight: FontWeight.w500,
        height: 1,
        color: zunoInk,
      ),
    );
    final initial = switch (shape) {
      AvatarShape.circle => CircleAvatar(
        radius: radius,
        backgroundColor: tone,
        foregroundColor: zunoInk,
        child: letter,
      ),
      AvatarShape.roundedSquare => SizedBox.square(
        dimension: diameter,
        child: DecoratedBox(
          decoration: BoxDecoration(color: tone, borderRadius: corners),
          child: Center(child: letter),
        ),
      ),
    };
    final avatarUrl = this.avatarUrl;
    if (avatarUrl == null) return initial;

    final image = ColoredBox(
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
    );

    return SizedBox.square(
      dimension: diameter,
      child: switch (shape) {
        AvatarShape.circle => ClipOval(child: image),
        AvatarShape.roundedSquare => ClipRRect(
          borderRadius: corners,
          child: image,
        ),
      },
    );
  }
}

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
