import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'server_name.dart';

enum _RoomIdKind {
  alias('#', 'alias'),
  roomId('!', 'roomid');

  const _RoomIdKind(this.sigil, this.hint);

  final String sigil;
  final String hint;
}

Future<String?> showLocalRoomDialog(
  BuildContext context, {
  required Client client,
}) async {
  final localId = await showDialog<String>(
    context: context,
    builder: (context) => const _LocalRoomDialog(),
  );
  if (localId == null) return null;
  return '$localId:${ownServerName(client)!}';
}

class _LocalRoomDialog extends StatefulWidget {
  const _LocalRoomDialog();

  @override
  State<_LocalRoomDialog> createState() => _LocalRoomDialogState();
}

class _LocalRoomDialogState extends State<_LocalRoomDialog> {
  final _controller = TextEditingController();
  _RoomIdKind _kind = _RoomIdKind.alias;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _controller.text.trim();
    final localPart = typed.startsWith(_kind.sigil)
        ? typed.substring(1)
        : typed;
    if (localPart.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop('${_kind.sigil}$localPart');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join room'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_RoomIdKind>(
            segments: const [
              ButtonSegment(
                value: _RoomIdKind.alias,
                label: Text('Alias'),
                icon: Icon(Icons.tag_outlined),
              ),
              ButtonSegment(
                value: _RoomIdKind.roomId,
                label: Text('Room ID'),
                icon: Icon(Icons.pin_outlined),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          const SizedBox(height: 16),
          TextField(
            autofillHints: null,
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              prefixText: _kind.sigil,
              border: const OutlineInputBorder(),
              hintText: _kind.hint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Join')),
      ],
    );
  }
}
