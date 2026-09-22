import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_roles.dart';

class MemberTile extends StatelessWidget {
  final Room room;
  final User user;
  final VoidCallback? onTap;

  const MemberTile({
    required this.room,
    required this.user,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final badge = memberBadge(room, user);
    return ListTile(
      leading: MxcAvatar(
        client: room.client,
        avatarUrl: user.avatarUrl,
        fallbackText: user.calcDisplayname(),
        radius: 18,
      ),
      title: Text(user.calcDisplayname()),
      subtitle: Text(withoutServer(user.id)),
      trailing: badge == null ? null : Text(badge),
      onTap: onTap,
    );
  }
}
