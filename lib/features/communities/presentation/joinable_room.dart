import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/rooms/membership/join_requests.dart';
import '../../../core/matrix/rooms/room_access.dart';
import '../../../core/matrix/rooms/room_title.dart';
import '../../../core/settings/matrix_experience.dart';
import '../../../core/ui/sheet.dart';
import '../../../core/ui/trailing_action_row.dart';
import '../../room_info/presentation/room_access_label.dart';
import '../../room_info/presentation/room_header.dart';
import '../../rooms/presentation/chat_row.dart';
import '../../rooms/presentation/room_kind_avatar.dart';

enum JoinEntry { join, ask, requested }

JoinEntry joinEntryFor(SpaceRoomsChunk$2 chunk, Set<String> asked) {
  if (listedRoomAccess(chunk.joinRule) != RoomAccess.askToJoin) {
    return JoinEntry.join;
  }
  if (asked.contains(chunk.roomId)) return JoinEntry.requested;
  return JoinEntry.ask;
}

class JoinableRoomRow extends StatelessWidget {
  final Client client;
  final SpaceRoomsChunk$2 chunk;
  final JoinEntry entry;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAct;

  const JoinableRoomRow({
    required this.client,
    required this.chunk,
    required this.entry,
    required this.busy,
    required this.onOpen,
    required this.onAct,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final title = listedRoomTitle(chunk, l10n);
    final topic = chunk.topic?.trim();
    final detail = joinDetails([
      if (entry != JoinEntry.join) RoomAccess.askToJoin.label(l10n),
      l10n.unitsMembers(chunk.numJoinedMembers),
      if (topic != null && topic.isNotEmpty) topic,
    ]);
    return InkWell(
      onTap: busy ? null : onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: TrailingActionRow(
          main: Row(
            children: [
              RoomKindAvatar(
                client: client,
                avatarUrl: chunk.avatarUrl,
                fallbackText: title,
                isDirect: false,
                radius: ChatRow.avatarRadius,
                toneSeed: chunk.roomId,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: _JoinButton(entry: entry, busy: busy, onPressed: onAct),
        ),
      ),
    );
  }
}

Future<bool> showJoinableRoomSheet(
  BuildContext context, {
  required Room community,
  required SpaceRoomsChunk$2 chunk,
  required bool busy,
}) async =>
    await showSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _JoinableRoomSheet(community: community, chunk: chunk, busy: busy),
    ) ??
    false;

class _JoinableRoomSheet extends ConsumerWidget {
  final Room community;
  final SpaceRoomsChunk$2 chunk;
  final bool busy;

  const _JoinableRoomSheet({
    required this.community,
    required this.chunk,
    required this.busy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final client = community.client;
    final alias = chunk.canonicalAlias;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoomHeader(
            client: client,
            avatarUrl: chunk.avatarUrl,
            title: listedRoomTitle(chunk, l10n),
            toneSeed: chunk.roomId,
            address: alias == null ? null : context.matrixIdLabel(alias),
            details: [
              if (chunk.encryption != null) const EncryptedLabel(),
              RoomAccessLabel.listed(chunk, client, l10n),
              RoomDetail(l10n.unitsMembers(chunk.numJoinedMembers)),
            ],
            topic: chunk.topic,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _JoinButton(
              entry: joinEntryFor(chunk, ref.watch(joinRequestsProvider)),
              busy: busy,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  final JoinEntry entry;
  final bool busy;
  final VoidCallback onPressed;

  const _JoinButton({
    required this.entry,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final onTap = busy ? null : onPressed;
    if (entry == JoinEntry.requested) {
      return OutlinedButton(
        onPressed: onTap,
        child: Text(l10n.communitiesRequested),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
      ),
      onPressed: onTap,
      child: Text(
        entry == JoinEntry.ask ? l10n.communitiesAsk : l10n.commonJoin,
      ),
    );
  }
}
