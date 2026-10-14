import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/route_settled.dart';
import '../../../core/ui/sheet.dart';
import '../../../core/ui/zuno_theme.dart';

String _nameOf(User user) {
  final name = user.displayName?.trim();
  return name == null || name.isEmpty ? withoutServer(user.id) : name;
}

Stream<void> _changesIn(Room room) => room.client.onRoomState.stream.where(
  (update) =>
      update.roomId == room.id && update.state.type == EventTypes.RoomMember,
);

class JoinRequestsBanner extends StatefulWidget {
  final Room room;

  const JoinRequestsBanner({required this.room, super.key});

  @override
  State<JoinRequestsBanner> createState() => _JoinRequestsBannerState();
}

class _JoinRequestsBannerState extends State<JoinRequestsBanner>
    with RouteSettled {
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = _changesIn(widget.room).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
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
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = _changesIn(widget.room).listen((_) => _refresh());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    if (pendingJoinRequests(widget.room).isEmpty) {
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
              onAnswered: _refresh,
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
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action(widget.room, widget.user.id);
      widget.onAnswered?.call();
    } catch (e, s) {
      reportCaught('answer join request', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, e, failed: failed))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
