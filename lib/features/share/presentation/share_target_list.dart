import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../rooms/presentation/room_kind_avatar.dart';

bool isShareTarget(Room room) =>
    room.membership == Membership.join && !room.isSpace && canPostInRoom(room);

List<Room> filterShareTargets(
  List<Room> rooms,
  String query,
  AppLocalizations l10n,
) {
  final needle = query.trim().toLowerCase();
  return [
    for (final room in rooms)
      if (isShareTarget(room) &&
          (needle.isEmpty ||
              roomTitle(room, l10n).toLowerCase().contains(needle)))
        room,
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

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = Theme.of(context).colorScheme.error;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ZunoTextField(
            autofillHints: null,
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.shareSearchChats,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<SyncUpdate>(
            stream: widget.client.onSync.stream,
            builder: (context, _) {
              final rooms = filterShareTargets(
                widget.client.rooms,
                _query.text,
                l10n,
              );
              if (rooms.isEmpty) {
                return Center(child: Text(l10n.shareNoChats));
              }
              return ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  final display = roomInviteDisplay(room, l10n);
                  final community = communitiesOf(room).firstOrNull;
                  return ListTile(
                    leading: RoomKindAvatar(
                      client: widget.client,
                      avatarUrl: display.avatarUrl,
                      fallbackText: display.title,
                      isDirect: room.isDirectChat,
                      toneSeed: roomToneSeed(room),
                      inCommunity: community == null
                          ? null
                          : (
                              avatarUrl: community.avatar,
                              name: roomTitle(community, l10n),
                              toneSeed: roomToneSeed(community),
                            ),
                    ),
                    title: Row(
                      children: [
                        if (!room.encrypted) ...[
                          Icon(notEncryptedIcon, size: 16, color: error),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            display.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: widget.trailing?.call(room),
                    onTap: () => widget.onTap(room),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
