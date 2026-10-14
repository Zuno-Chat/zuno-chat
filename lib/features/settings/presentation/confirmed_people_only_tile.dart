import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';

class ConfirmedPeopleOnlyTile extends ConsumerWidget {
  const ConfirmedPeopleOnlyTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final on = ref.watch(encryptToVerifiedSessionsOnlyProvider);
    final status = ref.watch(accountSecurityStatusProvider).value;
    final blocker = switch (status) {
      AccountSecurityStatus.noRecovery =>
        l10n.settingsConfirmedOnlyNeedsRecovery,
      AccountSecurityStatus.deviceLocked =>
        l10n.settingsConfirmedOnlyNeedsApproval,
      _ => null,
    };
    final canTurnOn = status != null && blocker == null;

    return SwitchListTile(
      secondary: const Icon(Icons.gpp_good_outlined),
      title: Text(l10n.settingsConfirmedOnlyTitle),
      subtitle: Text(
        on || blocker == null ? l10n.settingsConfirmedOnlySubtitle : blocker,
      ),
      value: on,
      onChanged: on || canTurnOn
          ? (value) => ref
                .read(encryptToVerifiedSessionsOnlyProvider.notifier)
                .set(value)
          : null,
    );
  }
}
