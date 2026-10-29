import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_name_check.dart';
import '../../../core/security/zuno_text_field.dart';

typedef NewRoom = ({String name, RoomAccess access});

Future<NewRoom?> showNewRoomDialog(
  BuildContext context, {
  String? title,
  String? hint,
  String? community,
}) => showDialog<NewRoom>(
  context: context,
  builder: (_) =>
      _NewRoomDialog(title: title, hint: hint, community: community),
);

class _NewRoomDialog extends StatefulWidget {
  final String? title;
  final String? hint;
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

  String _communityDescription(
    AppLocalizations l10n,
    RoomAccess access,
    String community,
  ) => access == RoomAccess.community
      ? l10n.roomsAnyoneInCommunityCanJoin(community)
      : access.description(l10n);

  void _submit() {
    final name = _controller.text.trim();
    final error = roomNameError(context.l10n, name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop<NewRoom>((name: name, access: _access));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final community = widget.community;
    return AlertDialog(
      title: Text(widget.title ?? l10n.roomsNewRoom),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZunoTextField(
            autofillHints: null,
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: widget.hint ?? l10n.roomsRoomName,
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
                      title: Text(access.label(l10n)),
                      subtitle: Text(
                        _communityDescription(l10n, access, community),
                      ),
                    ),
                ],
              ),
            )
          else ...[
            SegmentedButton<RoomAccess>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: RoomAccess.private,
                  icon: const Icon(Icons.public_off),
                  label: Text(RoomAccess.private.label(l10n)),
                ),
                ButtonSegment(
                  value: RoomAccess.public,
                  icon: const Icon(Icons.public),
                  label: Text(RoomAccess.public.label(l10n)),
                ),
              ],
              selected: {_access},
              onSelectionChanged: (selection) =>
                  setState(() => _access = selection.single),
            ),
            const SizedBox(height: 8),
            Text(
              _access.description(l10n),
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
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.roomsCreate)),
      ],
    );
  }
}
