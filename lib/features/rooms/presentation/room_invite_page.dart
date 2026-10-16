import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/notifications/room_invite_notification_provider.dart';
import '../../blocking/presentation/block_person.dart';
import '../../communities/presentation/community_page.dart';
import '../../reports/presentation/report_sheet.dart';

class RoomInvitePage extends ConsumerStatefulWidget {
  final Room room;
  final BlockPerson? blockPerson;

  const RoomInvitePage({required this.room, this.blockPerson, super.key});

  @override
  ConsumerState<RoomInvitePage> createState() => _RoomInvitePageState();
}

class _RoomInvitePageState extends ConsumerState<RoomInvitePage> {
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
    final l10n = context.l10n;
    setState(() => _busy = true);
    unawaited(cancelInviteNotification(widget.room));
    try {
      await action();
      if (!mounted) return;
      navigator.pop();
      if (join) {
        navigator.push(
          MaterialPageRoute(builder: (_) => pageForRoom(widget.room)),
        );
      }
    } catch (e, s) {
      reportCaught('answer invitation', e, s);
      if (mounted) setState(() => _busy = false);
      final failed = join ? l10n.roomsCouldNotJoin : l10n.roomsCouldNotDecline;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, e, failed: failed))),
      );
    }
  }

  Future<void> _reportAndDecline(String inviter) async {
    final room = widget.room;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final sent = await showReportSheet(
      context,
      title: l10n.roomsReportInvitation,
      explanation: l10n.roomsReportInvitationExplain,
      sendLabel: l10n.roomsReportAndDecline,
      onSend: (reason, note) => reportPerson(
        room.client,
        inviter,
        reason,
        note: note,
        roomId: room.id,
      ),
    );
    if (!sent || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.commonReportSent)));
    await _answer(() => declineInvite(room), join: false);
  }

  Future<void> _blockAndDecline(String inviter, String name) async {
    final navigator = Navigator.of(context);
    final blocked = await confirmAndBlockPerson(
      context,
      client: widget.room.client,
      userId: inviter,
      name: name,
      endCallsIn: ref.read(endCallsInProvider),
      block: widget.blockPerson,
    );
    if (!blocked) return;
    unawaited(cancelInviteNotification(widget.room));
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final l10n = context.l10n;
    final client = room.client;
    final inviter = inviterId(room);
    final inviterUser = inviter == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(inviter);
    final inviterName =
        inviterUser?.calcDisplayname() ??
        (inviter == null ? l10n.roomsSomeone : withoutServer(inviter));
    final isGroup = room.name.isNotEmpty;
    final isCommunity = room.isSpace;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.roomsInvitation)),
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
                  toneSeed: roomToneSeed(room),
                  radius: 40,
                  shape: AvatarShape.forRoom(room),
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
                isCommunity
                    ? l10n.roomsInvitedToCommunity(inviterName)
                    : isGroup
                    ? l10n.roomsInvitedToRoom(inviterName)
                    : l10n.roomsWantsToChat(inviterName),
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
                onPressed: _busy
                    ? null
                    : () => _answer(
                        () => room.join(waitForSync: true),
                        join: true,
                      ),
                child: Text(l10n.commonJoin),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _answer(() => declineInvite(room), join: false),
                child: Text(l10n.commonDecline),
              ),
              if (inviter != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => _reportAndDecline(inviter),
                  child: Text(l10n.roomsReportAndDecline),
                ),
                if (canBlockPerson(inviter))
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _blockAndDecline(inviter, inviterName),
                    child: Text(l10n.roomsBlockAndDecline),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
