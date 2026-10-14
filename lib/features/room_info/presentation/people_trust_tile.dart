import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
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
      return ListTile(
        dense: true,
        leading: const Icon(Icons.people_outline),
        title: Text(context.l10n.roomInfoPeople),
        subtitle: Text(context.l10n.commonLoading),
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
          others.length == 1
              ? withoutServer(others.single.id)
              : context.l10n.roomInfoPeople,
        ),
        subtitle: Text(context.l10n.roomInfoConfirmOnceJoined),
      );
    }

    if (others.length == 1) {
      return _PersonTrustRow(userId: others.single.id, room: room);
    }
    return _GroupTrustRow(room: room, others: others);
  }
}

String _confirmedSubtitle(BuildContext context, WidgetRef ref, String userId) {
  final l10n = context.l10n;
  final at = ref.watch(confirmedIdentityStoreProvider).confirmedAt(userId);
  if (at == null) return l10n.roomInfoCoversLater;
  return l10n.roomInfoConfirmedOn(DateLabels.of(context).longDate(at));
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
    final l10n = context.l10n;

    switch (state) {
      case UserTrustState.noIdentity:
        return ListTile(
          dense: true,
          leading: const Icon(Icons.person_outline),
          title: Text(name),
          subtitle: Text(l10n.roomInfoNoRecoverySetUp),
        );
      case UserTrustState.unconfirmed:
        return ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(l10n.verificationConfirmPerson(name)),
          subtitle: Text(l10n.roomInfoScanOrCompare),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => confirmPerson(context, ref, userId),
        );
      case UserTrustState.confirmed:
        return ListTile(
          leading: Icon(Icons.check_circle_outline, color: colors.primary),
          title: Text(l10n.roomInfoIsConfirmed(name)),
          subtitle: Text(_confirmedSubtitle(context, ref, userId)),
        );
      case UserTrustState.confirmedWithPendingDevice:
        return ListTile(
          leading: Icon(Icons.check_circle_outline, color: colors.primary),
          title: Text(l10n.roomInfoIsConfirmed(name)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_confirmedSubtitle(context, ref, userId)),
              Text(l10n.roomInfoPendingDevice),
            ],
          ),
          isThreeLine: true,
        );
      case UserTrustState.identityChanged:
        return ListTile(
          leading: Icon(attentionIcon, color: colors.error),
          title: Text(l10n.roomInfoPersonIdentityChanged(name)),
          subtitle: Text(l10n.roomInfoIdentityChangedHint),
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
        title: Text(context.l10n.roomInfoPeople),
        subtitle: Text(
          confirmed == 0
              ? context.l10n.roomInfoNobodyConfirmed
              : context.l10n.roomInfoConfirmedCount(confirmed, others.length),
        ),
      );
    }

    return ListTile(
      leading: Icon(attentionIcon, color: colors.error),
      title: Text(
        context.l10n.roomInfoGroupIdentityChanged(
          changed.length,
          withoutServer(changed.first.id),
        ),
      ),
      subtitle: Text(context.l10n.roomInfoConfirmThemAgain),
      trailing: const Icon(Icons.chevron_right_outlined),
      onTap: () => confirmPerson(context, ref, changed.first.id),
    );
  }
}
