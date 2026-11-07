import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/matrix/rooms/permissions/room_roles.dart';
import '../../../core/settings/matrix_experience.dart';

class MemberTile extends StatelessWidget {
  final Room room;
  final User user;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MemberTile({
    required this.room,
    required this.user,
    this.trailing,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final badge = memberBadge(room, user, context.l10n);
    return ListTile(
      leading: MxcAvatar(
        client: room.client,
        avatarUrl: user.avatarUrl,
        fallbackText: user.calcDisplayname(),
        toneSeed: user.id,
        radius: 18,
      ),
      title: Text(user.calcDisplayname()),
      subtitle: Text(context.matrixIdLabel(user.id)),
      trailing: trailing ?? (badge == null ? null : Text(badge)),
      onTap: onTap,
    );
  }
}
