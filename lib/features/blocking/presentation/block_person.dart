import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/rooms/official_room.dart';
import '../../../core/ui/close_own_route.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/notice.dart';

typedef BlockPerson = Future<void> Function(String userId);

typedef UnblockPerson = Future<void> Function(String userId);

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
      name: name,
      unblocking: false,
      leavesChat: client.getDirectChatFromUserId(userId) != null,
      run: () => block != null
          ? block(userId)
          : blockOnServer(client, userId, endCallsIn: endCallsIn),
    ),
  );
  if (blocked != true) return false;
  messenger.say(l10n.blockingBlocked(name));
  return true;
}

Future<bool> confirmAndUnblockPerson(
  BuildContext context, {
  required Client client,
  required String userId,
  required String name,
  UnblockPerson? unblock,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final unblocked = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BlockDialog(
      name: name,
      unblocking: true,
      leavesChat: false,
      run: () => (unblock ?? client.unignoreUser)(userId),
    ),
  );
  if (unblocked != true) return false;
  messenger.say(l10n.blockingUnblocked(name));
  return true;
}

Future<bool> blockAndReturnHome(
  BuildContext context, {
  required Client client,
  required String userId,
  required String name,
  required EndCallsIn endCallsIn,
  BlockPerson? block,
}) => _thenHome(
  Navigator.of(context),
  confirmAndBlockPerson(
    context,
    client: client,
    userId: userId,
    name: name,
    endCallsIn: endCallsIn,
    block: block,
  ),
);

Future<bool> unblockAndReturnHome(
  BuildContext context, {
  required Client client,
  required String userId,
  required String name,
  UnblockPerson? unblock,
}) => _thenHome(
  Navigator.of(context),
  confirmAndUnblockPerson(
    context,
    client: client,
    userId: userId,
    name: name,
    unblock: unblock,
  ),
);

Future<bool> _thenHome(NavigatorState navigator, Future<bool> done) async {
  final happened = await done;
  if (happened) navigator.popUntil((route) => route.isFirst);
  return happened;
}

Future<bool> unblockPerson(
  BuildContext context, {
  required Client client,
  required String userId,
  required String name,
  UnblockPerson? unblock,
}) {
  final l10n = context.l10n;
  return attempt(
    context,
    () => (unblock ?? client.unignoreUser)(userId),
    label: 'unblock person',
    failed: l10n.blockingUnblockFailed,
    succeeded: l10n.blockingUnblocked(name),
  );
}

class _BlockDialog extends StatefulWidget {
  final String name;
  final bool unblocking;
  final bool leavesChat;
  final Future<void> Function() run;

  const _BlockDialog({
    required this.name,
    required this.unblocking,
    required this.leavesChat,
    required this.run,
  });

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  bool _running = false;
  Object? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await widget.run();
    } catch (e, s) {
      reportCaught(widget.unblocking ? 'unblock person' : 'block person', e, s);
      if (mounted) {
        setState(() {
          _running = false;
          _error = e;
        });
      }
      return;
    }
    if (mounted) closeOwnRoute(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final l10n = context.l10n;
    final unblocking = widget.unblocking;
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        title: Text(
          unblocking
              ? l10n.blockingUnblockTitle(name)
              : l10n.blockingTitle(name),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unblocking
                  ? l10n.blockingUnblockExplanation(name)
                  : l10n.blockingExplanation(name),
            ),
            if (widget.leavesChat) ...[
              const SizedBox(height: 12),
              Text(l10n.blockingLeavesChat(name)),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              InlineError(
                failureMessage(
                  l10n,
                  error,
                  failed: unblocking
                      ? l10n.blockingUnblockFailed
                      : l10n.blockingFailed,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: _running ? null : _run,
            style: unblocking ? null : destructiveButtonStyle(context),
            child: Text(switch ((unblocking, _running)) {
              (false, false) => l10n.commonBlock,
              (false, true) => l10n.blockingInProgress,
              (true, false) => l10n.blockingUnblock,
              (true, true) => l10n.blockingUnblockInProgress,
            }),
          ),
        ],
      ),
    );
  }
}
