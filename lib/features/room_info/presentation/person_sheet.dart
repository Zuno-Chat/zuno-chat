import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/matrix/rooms/membership/rooms_in_common.dart';
import '../../../core/matrix/rooms/permissions/room_roles.dart';
import '../../../core/matrix/rooms/room_title.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/user_trust.dart';
import '../../../core/settings/matrix_experience.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/quick_action.dart';
import '../../../core/ui/sheet.dart';
import '../../blocking/presentation/block_person.dart';
import '../../chat/presentation/room_page.dart';
import '../../rooms/presentation/room_kind_avatar.dart';
import 'member_actions.dart';

bool canOpenPersonSheet(Room room, User user) => user.id != room.client.userID;

Future<MemberAction?> openPersonSheet(
  BuildContext context,
  WidgetRef ref, {
  required Room room,
  required User user,
  BlockPerson? blockPerson,
  UnblockPerson? unblockPerson,
}) async {
  final action = await showSheet<MemberAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PersonSheet(room: room, user: user),
  );
  if (action == null || !context.mounted) return null;
  final done = await actOnMember(
    context,
    ref,
    room,
    user,
    action,
    blockPerson: blockPerson,
    unblockPerson: unblockPerson,
  );
  return done ? action : null;
}

class _PersonSheet extends ConsumerStatefulWidget {
  final Room room;
  final User user;

  const _PersonSheet({required this.room, required this.user});

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  List<Room> _inCommon = const [];
  bool _showInCommon = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInCommon());
  }

  Future<void> _loadInCommon() => runBestEffort(() async {
    final rooms = await roomsInCommon(widget.room, widget.user.id);
    if (mounted) setState(() => _inCommon = rooms);
  }, label: 'rooms in common');

  void _openRoom(Room room) {
    final navigator = Navigator.of(context);
    navigator.pop();
    openChat(navigator, room);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final room = widget.room;
    final user = widget.user;
    final name = user.calcDisplayname();
    final badge = memberBadge(room, user, l10n);
    final actions = memberActionsFor(room, user);
    final quick = [
      for (final action in actions)
        if (!action.moderates) action,
    ];
    final moderation = [
      for (final action in actions)
        if (action.moderates) action,
    ];
    final confirmed = userTrustConfirmed(ref.watch(userTrustProvider(user.id)));
    final confirmedAt = confirmed
        ? ref.watch(confirmedIdentityStoreProvider).confirmedAt(user.id)
        : null;
    final blocked = room.client.ignoredUsers.contains(user.id);

    final details = [
      if (confirmed)
        ListTile(
          leading: Icon(
            confirmedPersonIcon,
            color: confirmedPersonColor(context),
          ),
          title: Text(l10n.roomInfoConfirmedPerson),
          subtitle: confirmedAt == null
              ? null
              : Text(DateLabels.of(context).longDate(confirmedAt)),
        ),
      if (blocked)
        ListTile(
          leading: Icon(
            Icons.do_not_disturb_on_outlined,
            color: theme.colorScheme.error,
          ),
          title: Text(l10n.roomInfoBlockedPerson),
        ),
      if (_inCommon.isNotEmpty) ...[
        ListTile(
          leading: const Icon(Icons.groups_outlined),
          title: Text(l10n.roomInfoRoomsInCommon(_inCommon.length)),
          trailing: Icon(
            _showInCommon
                ? Icons.expand_less_outlined
                : Icons.expand_more_outlined,
          ),
          onTap: () => setState(() => _showInCommon = !_showInCommon),
        ),
        if (_showInCommon)
          for (final shared in _inCommon)
            _SharedRoomTile(room: shared, onTap: () => _openRoom(shared)),
      ],
    ];

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              children: [
                MxcAvatar(
                  client: room.client,
                  avatarUrl: user.avatarUrl,
                  fallbackText: name,
                  toneSeed: user.id,
                  radius: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  context.matrixIdLabel(user.id),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (badge != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    badge,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (quick.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final action in quick)
                    Flexible(
                      child: QuickAction(
                        icon: action.icon,
                        label: action.label(l10n, room),
                        onTap: () => Navigator.of(context).pop(action),
                      ),
                    ),
                ],
              ),
            ),
          if (details.isNotEmpty) CardGroup(children: details),
          if (moderation.isNotEmpty)
            CardGroup(
              children: [
                for (final action in moderation)
                  ListTile(
                    leading: Icon(action.icon),
                    title: Text(action.label(l10n, room)),
                    onTap: () => Navigator.of(context).pop(action),
                  ),
              ],
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SharedRoomTile extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;

  const _SharedRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = roomTitle(room, context.l10n);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 56, right: 16),
      leading: RoomKindAvatar(
        client: room.client,
        avatarUrl: room.avatar,
        fallbackText: title,
        toneSeed: roomToneSeed(room),
        radius: 18,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
