import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/route_settled.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(ZunoRadius.large),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: several
              ? Row(
                  children: [
                    _Avatar(room: room, user: first),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Lines(
                        title:
                            '${_nameOf(first)} and ${_others(requests.length - 1)}',
                        subtitle: 'Ask to join',
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        await showJoinRequestsSheet(context, room);
                        if (mounted) setState(() {});
                      },
                      child: const Text('Review'),
                    ),
                  ],
                )
              : JoinRequestRow(
                  key: ValueKey(first.id),
                  room: room,
                  user: first,
                  subtitle: 'Asks to join',
                  padding: EdgeInsets.zero,
                  onAnswered: () => setState(() {}),
                ),
        ),
      ),
    );
  }
}

String _others(int count) => count == 1 ? '1 other' : '$count others';

bool _peopleCanAsk(Room room) => switch (room.joinRules) {
  JoinRules.knock || JoinRules.knockRestricted => true,
  _ => false,
};

Future<void> showJoinRequestsSheet(BuildContext context, Room room) =>
    showModalBottomSheet<void>(
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
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Asking to join ${roomTitle(room)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Letting someone in invites them to the room.',
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
      title: 'Asking to join',
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
    setState(() => _busy = true);
    try {
      await action(widget.room, widget.user.id);
      widget.onAnswered?.call();
    } catch (e) {
      logCaught('answer join request', e);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(e, failed: failed))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final who = Row(
      children: [
        _Avatar(room: widget.room, user: user),
        const SizedBox(width: 12),
        Expanded(
          child: _Lines(
            title: _nameOf(user),
            subtitle: widget.subtitle ?? withoutServer(user.id),
          ),
        ),
      ],
    );
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          who,
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
                        failed: 'Could not decline the request.',
                      ),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _answer(letIn, failed: 'Could not let them in.'),
                child: const Text('Let in'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Room room;
  final User user;

  const _Avatar({required this.room, required this.user});

  @override
  Widget build(BuildContext context) => MxcAvatar(
    client: room.client,
    avatarUrl: user.avatarUrl,
    fallbackText: _nameOf(user),
    toneSeed: user.id,
  );
}

class _Lines extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Lines({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
    );
  }
}
