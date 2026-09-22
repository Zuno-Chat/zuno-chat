import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/user_trust.dart';
import '../../verification/presentation/confirm_person.dart';

class PeopleTrustTile extends ConsumerWidget {
  final Room room;
  final List<User>? participants;

  const PeopleTrustTile({
    required this.room,
    required this.participants,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = this.participants;
    if (participants == null) {
      return const ListTile(
        dense: true,
        leading: Icon(Icons.people_outline),
        title: Text('People'),
        subtitle: Text('Loading…'),
      );
    }

    final client = room.client;
    final others = participants.where((u) => u.id != client.userID).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    if (isAwaitingInviteAcceptance(room)) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.schedule_outlined),
        title: Text(
          others.length == 1 ? withoutServer(others.single.id) : 'People',
        ),
        subtitle: const Text('You can confirm them once they join'),
      );
    }

    if (others.length == 1) {
      return _PersonTrustRow(userId: others.single.id, room: room);
    }
    return _GroupTrustRow(room: room, others: others);
  }
}

String _confirmedSubtitle(WidgetRef ref, String userId) {
  const covers =
      'Covers any device they add later. You will not need to do this again.';
  final at = ref.watch(confirmedIdentityStoreProvider).confirmedAt(userId);
  if (at == null) return covers;
  return 'Confirmed ${_formatDate(at)}. $covers';
}

String _formatDate(DateTime at) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}

class _PersonTrustRow extends ConsumerWidget {
  final String userId;
  final Room room;

  const _PersonTrustRow({required this.userId, required this.room});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userTrustProvider(userId));
    final name = withoutServer(userId);
    final colors = Theme.of(context).colorScheme;

    switch (state) {
      case UserTrustState.noIdentity:
        return ListTile(
          dense: true,
          leading: const Icon(Icons.person_outline),
          title: Text(name),
          subtitle: const Text(
            'They have not set up recovery, so there is nothing to confirm yet',
          ),
        );
      case UserTrustState.unconfirmed:
        return ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text('Confirm it is really $name'),
          subtitle: const Text(
            'Scan their code in person, or compare pictures on a call',
          ),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => confirmPerson(context, ref, userId),
        );
      case UserTrustState.confirmed:
        return ListTile(
          leading: Icon(Icons.check_circle_outline, color: colors.primary),
          title: Text('$name is confirmed'),
          subtitle: Text(_confirmedSubtitle(ref, userId)),
        );
      case UserTrustState.confirmedWithPendingDevice:
        return ListTile(
          leading: Icon(Icons.check_circle_outline, color: colors.primary),
          title: Text('$name is confirmed'),
          subtitle: Text(
            '${_confirmedSubtitle(ref, userId)}\n'
            'They have a device they have not approved yet.',
          ),
          isThreeLine: true,
        );
      case UserTrustState.identityChanged:
        return ListTile(
          leading: Icon(attentionIcon, color: colors.error),
          title: Text("$name's security details changed"),
          subtitle: const Text(
            'Usually a new device or a reinstall. Confirm them again.',
          ),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => confirmPerson(context, ref, userId),
        );
    }
  }
}

class _GroupTrustRow extends ConsumerWidget {
  final Room room;
  final List<User> others;

  const _GroupTrustRow({required this.room, required this.others});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changed = others
        .where(
          (u) =>
              ref.watch(userTrustProvider(u.id)) ==
              UserTrustState.identityChanged,
        )
        .toList();
    final colors = Theme.of(context).colorScheme;

    if (changed.isEmpty) {
      final confirmed = others
          .where(
            (u) => switch (ref.watch(userTrustProvider(u.id))) {
              UserTrustState.confirmed ||
              UserTrustState.confirmedWithPendingDevice => true,
              _ => false,
            },
          )
          .length;
      return ListTile(
        dense: true,
        leading: const Icon(Icons.people_outline),
        title: const Text('People'),
        subtitle: Text(
          confirmed == 0
              ? 'Nobody here is confirmed yet'
              : '$confirmed of ${others.length} confirmed',
        ),
      );
    }

    return ListTile(
      leading: Icon(attentionIcon, color: colors.error),
      title: Text(
        changed.length == 1
            ? "${withoutServer(changed.single.id)}'s security details changed"
            : '${changed.length} people’s security details changed',
      ),
      subtitle: const Text('Confirm them again'),
      trailing: const Icon(Icons.chevron_right_outlined),
      onTap: () => confirmPerson(context, ref, changed.first.id),
    );
  }
}
