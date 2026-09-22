import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/official_room.dart';

typedef BlockPerson = Future<void> Function(String userId);

bool canBlockPerson(String userId) => userId != officialNoticesUserId;

Future<void> blockOnServer(Client client, String userId) =>
    client.ignoreUser(userId);

Future<bool> confirmAndBlockPerson(
  BuildContext context, {
  required Client client,
  required String userId,
  required String name,
  BlockPerson? block,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final blocked = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BlockDialog(
      userId: userId,
      name: name,
      leavesChat: client.getDirectChatFromUserId(userId) != null,
      block: block ?? (userId) => blockOnServer(client, userId),
    ),
  );
  if (blocked != true) return false;
  messenger.showSnackBar(SnackBar(content: Text('$name blocked')));
  return true;
}

class _BlockDialog extends StatefulWidget {
  final String userId;
  final String name;
  final bool leavesChat;
  final BlockPerson block;

  const _BlockDialog({
    required this.userId,
    required this.name,
    required this.leavesChat,
    required this.block,
  });

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  bool _blocking = false;
  bool _failed = false;

  Future<void> _block() async {
    final navigator = Navigator.of(context);
    setState(() {
      _blocking = true;
      _failed = false;
    });
    try {
      await widget.block(widget.userId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _blocking = false;
          _failed = true;
        });
      }
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    return PopScope(
      canPop: !_blocking,
      child: AlertDialog(
        title: Text('Block $name?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Messages and invitations from $name will no longer reach you. '
              'In rooms you share, their messages are hidden. They are not '
              'told that you blocked them. You can unblock them in Settings.',
            ),
            if (widget.leavesChat) ...[
              const SizedBox(height: 12),
              Text(
                'You leave your chat with $name, and unblocking does not '
                'bring it back.',
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(
                'Not blocked. Try again.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _blocking
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _blocking ? null : _block,
            child: Text(_blocking ? 'Blocking…' : 'Block'),
          ),
        ],
      ),
    );
  }
}
