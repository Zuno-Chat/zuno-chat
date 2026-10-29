import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_changes.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/route_settled.dart';
import '../../../core/ui/sheet.dart';
import '../../../core/ui/zuno_theme.dart';

String _nameOf(User user) {
  final name = user.displayName?.trim();
  return name == null || name.isEmpty ? withoutServer(user.id) : name;
}

class JoinRequestsBanner extends StatefulWidget {
  final Room room;

  const JoinRequestsBanner({required this.room, super.key});

  @override
  State<JoinRequestsBanner> createState() => _JoinRequestsBannerState();
}

class _JoinRequestsBannerState extends State<JoinRequestsBanner>
    with RouteSettled {
  @override
  void onRouteSettled() {
    final room = widget.room;
    if (!canAnswerJoinRequests(room)) return;
    unawaited(
      runBestEffort(() async {
        await room.postLoad();
        if (!_peopleCanAsk(room)) return;
        await room.requestParticipants(const [Membership.knock], true, true);
        if (mounted) setState(() {});
      }, label: 'join requests'),
    );
  }

  @override
  Widget build(BuildContext context) => RoomChangesBuilder(
    changes: RoomChanges.state(widget.room),
    builder: _banner,
  );

  Widget _banner(BuildContext context) {
    final room = widget.room;
    if (!canAnswerJoinRequests(room)) return const SizedBox.shrink();
    final requests = pendingJoinRequests(room);
    if (requests.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final first = requests.first;
    final several = requests.length > 1;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(ZunoRadius.large),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: several
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Who(
                      room: room,
                      user: first,
                      title: l10n.communitiesNameAndOthers(
                        _nameOf(first),
                        requests.length - 1,
                      ),
                      subtitle: l10n.communitiesAskToJoin,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        onPressed: () async {
                          await showJoinRequestsSheet(context, room);
                          if (mounted) setState(() {});
                        },
                        child: Text(l10n.commonReview),
                      ),
                    ),
                  ],
                )
              : JoinRequestRow(
                  key: ValueKey(first.id),
                  room: room,
                  user: first,
                  subtitle: l10n.communitiesAsksToJoin,
                  padding: EdgeInsets.zero,
                  onAnswered: () => setState(() {}),
                ),
        ),
      ),
    );
  }
}

bool _peopleCanAsk(Room room) => switch (room.joinRules) {
  JoinRules.knock || JoinRules.knockRestricted => true,
  _ => false,
};

Future<void> showJoinRequestsSheet(BuildContext context, Room room) =>
    showSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _JoinRequestsSheet(room: room),
    );

class _JoinRequestsSheet extends StatefulWidget {
  final Room room;

  const _JoinRequestsSheet({required this.room});

  @override
  State<_JoinRequestsSheet> createState() => _JoinRequestsSheetState();
}

class _JoinRequestsSheetState extends State<_JoinRequestsSheet> {
  bool _closeIfAnswered() {
    if (pendingJoinRequests(widget.room).isNotEmpty) return false;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    }
    return true;
  }

  void _answered() {
    if (mounted && !_closeIfAnswered()) setState(() {});
  }

  @override
  Widget build(BuildContext context) => RoomChangesBuilder(
    changes: RoomChanges.state(widget.room),
    onChange: _closeIfAnswered,
    builder: _sheet,
  );

  Widget _sheet(BuildContext context) {
    final theme = Theme.of(context);
    final room = widget.room;
    final requests = pendingJoinRequests(room);
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              l10n.communitiesAskingToJoinRoom(roomTitle(room, l10n)),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              l10n.communitiesLetInInvites,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final user in requests)
            JoinRequestRow(
              key: ValueKey(user.id),
              room: room,
              user: user,
              onAnswered: _answered,
            ),
        ],
      ),
    );
  }
}

class JoinRequestsSection extends StatefulWidget {
  final Room room;

  const JoinRequestsSection({required this.room, super.key});

  @override
  State<JoinRequestsSection> createState() => _JoinRequestsSectionState();
}

class _JoinRequestsSectionState extends State<JoinRequestsSection> {
  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    if (!canAnswerJoinRequests(room)) return const SizedBox.shrink();
    final requests = pendingJoinRequests(room);
    if (requests.isEmpty) return const SizedBox.shrink();
    return CardGroup(
      title: context.l10n.communitiesAskingToJoin,
      children: [
        for (final user in requests)
          JoinRequestRow(
            key: ValueKey(user.id),
            room: room,
            user: user,
            onAnswered: () => setState(() {}),
          ),
      ],
    );
  }
}

class JoinRequestRow extends StatefulWidget {
  final Room room;
  final User user;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onAnswered;

  const JoinRequestRow({
    required this.room,
    required this.user,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 12, 8),
    this.onAnswered,
    super.key,
  });

  @override
  State<JoinRequestRow> createState() => _JoinRequestRowState();
}

class _JoinRequestRowState extends State<JoinRequestRow> {
  bool _busy = false;

  Future<void> _answer(
    Future<void> Function(Room room, String userId) action, {
    required String failed,
  }) async {
    setState(() => _busy = true);
    final answered = await attempt(
      context,
      () => action(widget.room, widget.user.id),
      label: 'answer join request',
      failed: failed,
    );
    if (answered) widget.onAnswered?.call();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final l10n = context.l10n;
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Who(
            room: widget.room,
            user: user,
            title: _nameOf(user),
            subtitle: widget.subtitle ?? withoutServer(user.id),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 4,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _answer(
                        declineJoinRequest,
                        failed: l10n.communitiesDeclineFailed,
                      ),
                child: Text(l10n.commonDecline),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _answer(letIn, failed: l10n.communitiesLetInFailed),
                child: Text(l10n.communitiesLetIn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Who extends StatelessWidget {
  final Room room;
  final User user;
  final String title;
  final String subtitle;

  const _Who({
    required this.room,
    required this.user,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        MxcAvatar(
          client: room.client,
          avatarUrl: user.avatarUrl,
          fallbackText: _nameOf(user),
          toneSeed: user.id,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
