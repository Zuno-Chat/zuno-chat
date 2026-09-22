import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/notifications/invite_notification_provider.dart';
import '../../blocking/presentation/block_person.dart';
import '../../chat/presentation/room_page.dart';
import '../../reports/presentation/report_sheet.dart';

class RoomInvitePage extends StatefulWidget {
  final Room room;
  final BlockPerson? blockPerson;

  const RoomInvitePage({required this.room, this.blockPerson, super.key});

  @override
  State<RoomInvitePage> createState() => _RoomInvitePageState();
}

class _RoomInvitePageState extends State<RoomInvitePage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadInviteMembers(widget.room).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _answer(
    Future<void> Function() action, {
    required bool join,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    unawaited(cancelInviteNotification(widget.room));
    try {
      await action();
      if (!mounted) return;
      navigator.pop();
      if (join) {
        navigator.push(
          MaterialPageRoute(builder: (_) => RoomPage(room: widget.room)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reportAndDecline(String inviter) async {
    final room = widget.room;
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showReportSheet(
      context,
      title: 'Report invitation',
      explanation:
          'The report goes to Zuno and names who invited you. The invitation '
          'is declined once the report is sent.',
      sendLabel: 'Report and decline',
      onSend: (reason, note) => reportPerson(
        room.client,
        inviter,
        reason,
        note: note,
        roomId: room.id,
      ),
    );
    if (!sent || !mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Report sent')));
    await _answer(room.leave, join: false);
  }

  Future<void> _blockAndDecline(String inviter, String name) async {
    final navigator = Navigator.of(context);
    final blocked = await confirmAndBlockPerson(
      context,
      client: widget.room.client,
      userId: inviter,
      name: name,
      block: widget.blockPerson,
    );
    if (!blocked) return;
    unawaited(cancelInviteNotification(widget.room));
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final client = room.client;
    final inviter = inviterId(room);
    final inviterUser = inviter == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(inviter);
    final inviterName =
        inviterUser?.calcDisplayname() ??
        (inviter == null ? 'Someone' : withoutServer(inviter));
    final isGroup = room.name.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Invitation')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: MxcAvatar(
                  client: client,
                  avatarUrl: isGroup ? room.avatar : inviterUser?.avatarUrl,
                  fallbackText: isGroup ? room.name : inviterName,
                  radius: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isGroup ? room.name : inviterName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                isGroup
                    ? '$inviterName invited you to this room.'
                    : '$inviterName wants to chat with you.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (inviter != null && inviterUser?.displayName != null) ...[
                const SizedBox(height: 4),
                Text(
                  withoutServer(inviter),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : () => _answer(room.join, join: true),
                child: const Text('Join'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _answer(room.leave, join: false),
                child: const Text('Decline'),
              ),
              if (inviter != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => _reportAndDecline(inviter),
                  child: const Text('Report and decline'),
                ),
                if (canBlockPerson(inviter))
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _blockAndDecline(inviter, inviterName),
                    child: const Text('Block and decline'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
