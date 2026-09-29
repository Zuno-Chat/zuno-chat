import 'package:flutter/material.dart';

import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_name_check.dart';

typedef NewRoom = ({String name, RoomAccess access});

Future<NewRoom?> showNewRoomDialog(
  BuildContext context, {
  String title = 'New room',
  String hint = 'Room name',
  String? community,
}) => showDialog<NewRoom>(
  context: context,
  builder: (_) =>
      _NewRoomDialog(title: title, hint: hint, community: community),
);

class _NewRoomDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String? community;

  const _NewRoomDialog({
    required this.title,
    required this.hint,
    this.community,
  });

  @override
  State<_NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends State<_NewRoomDialog> {
  final _controller = TextEditingController();
  late RoomAccess _access = widget.community == null
      ? RoomAccess.private
      : RoomAccess.community;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _communityDescription(RoomAccess access, String community) =>
      access == RoomAccess.community
      ? 'Anyone in $community can join'
      : access.description;

  void _submit() {
    final name = _controller.text.trim();
    final error = roomNameError(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop<NewRoom>((name: name, access: _access));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final community = widget.community;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofillHints: null,
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.hint,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          if (community != null)
            RadioGroup<RoomAccess>(
              groupValue: _access,
              onChanged: (access) {
                if (access != null) setState(() => _access = access);
              },
              child: Column(
                children: [
                  for (final access in const [
                    RoomAccess.community,
                    RoomAccess.askToJoin,
                    RoomAccess.private,
                  ])
                    RadioListTile<RoomAccess>(
                      value: access,
                      contentPadding: EdgeInsets.zero,
                      title: Text(access.label),
                      subtitle: Text(_communityDescription(access, community)),
                    ),
                ],
              ),
            )
          else ...[
            SegmentedButton<RoomAccess>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: RoomAccess.private,
                  icon: Icon(Icons.public_off),
                  label: Text('Private'),
                ),
                ButtonSegment(
                  value: RoomAccess.public,
                  icon: Icon(Icons.public),
                  label: Text('Public'),
                ),
              ],
              selected: {_access},
              onSelectionChanged: (selection) =>
                  setState(() => _access = selection.single),
            ),
            const SizedBox(height: 8),
            Text(
              _access.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
