import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/official_room.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/notice.dart';

typedef BlockPerson = Future<void> Function(String userId);

bool canBlockPerson(String userId) => userId != officialNoticesUserId;

Future<void> blockOnServer(
  Client client,
  String userId, {
  required EndCallsIn endCallsIn,
}) async {
  await endCallsIn([
    for (final room in client.rooms)
      if (room.directChatMatrixID == userId) room.id,
  ]);
  await client.ignoreUser(userId);
}

Future<bool> confirmAndBlockPerson(
  BuildContext context, {
  required Client client,
  required String userId,
  required String name,
  required EndCallsIn endCallsIn,
  BlockPerson? block,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final blocked = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BlockDialog(
      userId: userId,
      name: name,
      leavesChat: client.getDirectChatFromUserId(userId) != null,
      block:
          block ??
          (userId) => blockOnServer(client, userId, endCallsIn: endCallsIn),
    ),
  );
  if (blocked != true) return false;
  messenger.say(l10n.blockingBlocked(name));
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
  Object? _error;

  Future<void> _block() async {
    final navigator = Navigator.of(context);
    setState(() {
      _blocking = true;
      _error = null;
    });
    try {
      await widget.block(widget.userId);
    } catch (e, s) {
      reportCaught('block person', e, s);
      if (mounted) {
        setState(() {
          _blocking = false;
          _error = e;
        });
      }
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final l10n = context.l10n;
    return PopScope(
      canPop: !_blocking,
      child: AlertDialog(
        title: Text(l10n.blockingTitle(name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.blockingExplanation(name)),
            if (widget.leavesChat) ...[
              const SizedBox(height: 12),
              Text(l10n.blockingLeavesChat(name)),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              InlineError(
                failureMessage(l10n, error, failed: l10n.blockingFailed),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _blocking
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: _blocking ? null : _block,
            style: destructiveButtonStyle(context),
            child: Text(_blocking ? l10n.blockingInProgress : l10n.commonBlock),
          ),
        ],
      ),
    );
  }
}
