import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/notifications/room_invite_notification_provider.dart';
import '../../../core/ui/notice.dart';
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
    final l10n = context.l10n;
    setState(() => _busy = true);
    unawaited(cancelInviteNotification(widget.room));
    final answered = await attempt(
      context,
      action,
      label: 'answer invitation',
      failed: join ? l10n.roomsCouldNotJoin : l10n.roomsCouldNotDecline,
    );
    if (!mounted) return;
    if (!answered) {
      setState(() => _busy = false);
      return;
    }
    navigator.pop();
    if (join) {
      navigator.push(
        MaterialPageRoute(builder: (_) => pageForRoom(widget.room)),
      );
    }
  }

  Future<void> _reportAndDecline(String inviter) async {
    final room = widget.room;
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
    final view = incomingInviteView(room, l10n);
    final inviter = view.inviterId;

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
                  client: room.client,
                  avatarUrl: view.avatarUrl,
                  fallbackText: view.name,
                  toneSeed: roomToneSeed(room),
                  radius: 40,
                  shape: AvatarShape.forRoom(room),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                view.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                view.community
                    ? l10n.roomsInvitedToCommunity(view.inviterName)
                    : view.group
                    ? l10n.roomsInvitedToRoom(view.inviterName)
                    : l10n.roomsWantsToChat(view.inviterName),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (inviter != null && view.inviterNamed) ...[
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
                        () => acceptInvite(room, waitForSync: true),
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
                        : () => _blockAndDecline(inviter, view.inviterName),
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
