import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../rooms/presentation/room_kind_avatar.dart';

List<Room> filterShareTargets(
  List<Room> rooms,
  String query,
  AppLocalizations l10n,
) {
  final needle = query.trim().toLowerCase();
  return [
    for (final room in rooms)
      if (room.membership == Membership.join &&
          !room.isSpace &&
          canPostInRoom(room) &&
          (needle.isEmpty ||
              roomTitle(room, l10n).toLowerCase().contains(needle)))
        room,
  ];
}

class SharePickerPage extends StatefulWidget {
  final Client client;
  final Widget Function(Room room) destination;

  const SharePickerPage({
    required this.client,
    required this.destination,
    super.key,
  });

  @override
  State<SharePickerPage> createState() => _SharePickerPageState();
}

class _SharePickerPageState extends State<SharePickerPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _pick(Room room) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.destination(room)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTo)),
      body: Column(
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
                    return ListTile(
                      leading: RoomKindAvatar(
                        client: widget.client,
                        avatarUrl: display.avatarUrl,
                        fallbackText: display.title,
                        isDirect: room.isDirectChat,
                        toneSeed: roomToneSeed(room),
                      ),
                      title: Text(
                        display.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _pick(room),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
