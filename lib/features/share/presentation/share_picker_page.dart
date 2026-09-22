import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_title.dart';
import '../../rooms/presentation/room_kind_avatar.dart';

List<Room> filterShareTargets(List<Room> rooms, String query) {
  final needle = query.trim().toLowerCase();
  return [
    for (final room in rooms)
      if (room.membership == Membership.join &&
          (needle.isEmpty || roomTitle(room).toLowerCase().contains(needle)))
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
    return Scaffold(
      appBar: AppBar(title: const Text('Share to')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              autofillHints: null,
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search chats',
                border: OutlineInputBorder(),
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
                );
                if (rooms.isEmpty) {
                  return const Center(child: Text('No chats found'));
                }
                return ListView.builder(
                  itemCount: rooms.length,
                  itemBuilder: (context, i) {
                    final room = rooms[i];
                    final display = roomInviteDisplay(room);
                    return ListTile(
                      leading: RoomKindAvatar(
                        client: widget.client,
                        avatarUrl: display.avatarUrl,
                        fallbackText: display.title,
                        isDirect: room.isDirectChat,
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
