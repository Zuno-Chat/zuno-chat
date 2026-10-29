import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_encryption.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/search_field.dart';
import '../../rooms/presentation/room_kind_avatar.dart';

bool isShareTarget(Room room) =>
    room.membership == Membership.join && !room.isSpace && canPostInRoom(room);

typedef ShareTarget = ({
  Room room,
  String title,
  Uri? avatarUrl,
  CommunityMark? community,
  String search,
});

List<ShareTarget> shareTargets(List<Room> rooms, AppLocalizations l10n) {
  final byId = {for (final room in rooms) room.id: room};
  final communityOf = <String, CommunityMark>{};
  for (final community in rooms.where(isJoinedCommunity)) {
    final mark = (
      avatarUrl: community.avatar,
      name: roomTitle(community, l10n),
      toneSeed: roomToneSeed(community),
    );
    for (final room in communityRooms(community, lookup: (id) => byId[id])) {
      communityOf.putIfAbsent(room.id, () => mark);
    }
  }
  return [
    for (final room in rooms)
      if (isShareTarget(room)) _shareTarget(room, communityOf[room.id], l10n),
  ];
}

ShareTarget _shareTarget(
  Room room,
  CommunityMark? community,
  AppLocalizations l10n,
) {
  final display = roomInviteDisplay(room, l10n);
  return (
    room: room,
    title: display.title,
    avatarUrl: display.avatarUrl,
    community: community,
    search: display.title.toLowerCase(),
  );
}

List<ShareTarget> matchingShareTargets(
  List<ShareTarget> targets,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return targets;
  return [
    for (final target in targets)
      if (target.search.contains(needle)) target,
  ];
}

class ShareTargetList extends StatefulWidget {
  final Client client;
  final void Function(Room room) onTap;
  final Widget Function(Room room)? trailing;

  const ShareTargetList({
    required this.client,
    required this.onTap,
    this.trailing,
    super.key,
  });

  @override
  State<ShareTargetList> createState() => _ShareTargetListState();
}

class _ShareTargetListState extends State<ShareTargetList> {
  final _query = TextEditingController();
  late final StreamSubscription<SyncUpdate> _syncSub;
  List<ShareTarget>? _targets;

  @override
  void initState() {
    super.initState();
    _syncSub = widget.client.onSync.stream.listen(
      (_) => setState(() => _targets = null),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _targets = null;
  }

  @override
  void dispose() {
    unawaited(_syncSub.cancel());
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final targets = _targets ??= shareTargets(widget.client.rooms, l10n);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SearchField(hint: l10n.shareSearchChats, controller: _query),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _query,
            builder: (context, _) {
              final shown = matchingShareTargets(targets, _query.text);
              if (shown.isEmpty) {
                return Center(child: Text(l10n.shareNoChats));
              }
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) => _row(context, shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ShareTarget target) {
    final room = target.room;
    return ListTile(
      leading: RoomKindAvatar(
        client: widget.client,
        avatarUrl: target.avatarUrl,
        fallbackText: target.title,
        isDirect: room.isDirectChat,
        toneSeed: roomToneSeed(room),
        inCommunity: target.community,
      ),
      title: Row(
        children: [
          if (!sendsEncrypted(room)) ...[
            const NotEncryptedMark(size: 16),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              target.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: widget.trailing?.call(room),
      onTap: () => widget.onTap(room),
    );
  }
}
