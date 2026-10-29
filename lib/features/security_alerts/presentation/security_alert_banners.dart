import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/alerts/room_security_alerts_provider.dart';
import '../../../core/security/alerts/security_alert.dart';
import '../../../core/security/alerts/security_alert_detection.dart';
import '../../../core/security/alerts/security_alerts_provider.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/alert_banner.dart';
import '../../settings/presentation/active_sessions_page.dart';
import '../../settings/presentation/security_status_action.dart';
import '../../verification/presentation/confirm_person.dart';

class SecurityAlertBanners extends ConsumerWidget {
  final Room? room;

  const SecurityAlertBanners.account({super.key}) : room = null;

  const SecurityAlertBanners.room(Room this.room, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = this.room;
    final alerts = room == null
        ? ref.watch(accountSecurityAlertsProvider)
        : ref.watch(roomSecurityAlertsProvider(room));
    if (alerts.isEmpty) return const SizedBox.shrink();
    final reset = alerts.whereType<RecoveryResetAlert>().firstOrNull;
    final identityChanges = alerts.whereType<IdentityChangedAlert>().toList();
    final signIns = alerts.whereType<NewSignInAlert>().toList();
    final status = alerts.whereType<AccountStatusAlert>().firstOrNull;
    final unvouched = alerts.whereType<UnvouchedDeviceAlert>().firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reset != null) _recoveryReset(context, ref, reset),
        if (identityChanges.isNotEmpty)
          _identityChanged(context, ref, identityChanges),
        if (signIns.isNotEmpty) _newSignIn(context, ref, signIns),
        if (status != null) _accountStatus(context, ref, status),
        if (unvouched != null) _unvouchedDevice(context, ref, unvouched),
      ],
    );
  }

  void _openDevices(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ActiveSessionsPage()));

  Widget _recoveryReset(
    BuildContext context,
    WidgetRef ref,
    RecoveryResetAlert alert,
  ) {
    final text = recoveryResetText(context.l10n);
    return AlertBanner(
      icon: attentionIcon,
      title: text.title,
      body: text.body,
      actionLabel: context.l10n.commonReview,
      onAction: () => _openDevices(context),
      onDismiss: () => ref.read(securityAlertsProvider.notifier).dismiss(alert),
    );
  }

  Widget _identityChanged(
    BuildContext context,
    WidgetRef ref,
    List<IdentityChangedAlert> alerts,
  ) {
    final l10n = context.l10n;
    final first = alerts.first.userId;
    return AlertBanner(
      icon: attentionIcon,
      title: l10n.chatIdentityChanged(alerts.length, withoutServer(first)),
      body: l10n.chatIdentityChangedHint,
      actionLabel: l10n.chatIdentityChangedConfirm,
      onAction: () => confirmPerson(context, ref, first),
    );
  }

  Widget _newSignIn(
    BuildContext context,
    WidgetRef ref,
    List<NewSignInAlert> alerts,
  ) {
    final l10n = context.l10n;
    final first = alerts.first;
    final text = newSignInText(l10n, first);
    final seenAt = first.seenAt;
    final labels = DateLabels.of(context);
    final detail = [
      if (seenAt != null) labels.dayAndTime(seenAt, now: clock.now()),
      ?first.ipAddress,
    ].join(' · ');
    return AlertBanner(
      icon: attentionIcon,
      title: text.title,
      body: text.body,
      detail: detail.isEmpty ? null : detail,
      footnote: alerts.length > 1
          ? l10n.roomsMoreSignIns(alerts.length - 1)
          : null,
      actionLabel: l10n.commonReview,
      onAction: () => _openDevices(context),
      onDismiss: () {
        ref.read(securityAlertsProvider.notifier).dismiss(first);
        ref
            .read(dismissedSecurityStatusProvider.notifier)
            .dismiss(AccountSecurityStatus.deviceWaiting);
      },
    );
  }

  Widget _accountStatus(
    BuildContext context,
    WidgetRef ref,
    AccountStatusAlert alert,
  ) {
    final copy = accountSecurityCopy(context.l10n, alert.status);
    return AlertBanner(
      icon: attentionIcon,
      title: copy.title,
      body: copy.body,
      actionLabel: copy.action,
      onAction: () => runSecurityStatusAction(context, ref, alert.status),
      onDismiss: () => ref
          .read(dismissedSecurityStatusProvider.notifier)
          .dismiss(alert.status),
    );
  }

  Widget _unvouchedDevice(
    BuildContext context,
    WidgetRef ref,
    UnvouchedDeviceAlert alert,
  ) {
    final text = unvouchedDeviceText(context.l10n, withoutServer(alert.userId));
    return AlertBanner(
      icon: attentionIcon,
      title: text.title,
      body: text.body,
      onDismiss: () => ref.read(securityAlertsProvider.notifier).dismiss(alert),
    );
  }
}
