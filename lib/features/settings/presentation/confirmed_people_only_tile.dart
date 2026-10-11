import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';

class ConfirmedPeopleOnlyTile extends ConsumerWidget {
  const ConfirmedPeopleOnlyTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(encryptToVerifiedSessionsOnlyProvider);
    final status = ref.watch(accountSecurityStatusProvider).value;
    final blocker = switch (status) {
      AccountSecurityStatus.noRecovery => 'Set up recovery to turn this on',
      AccountSecurityStatus.deviceLocked =>
        'Approve this device to turn this on',
      _ => null,
    };
    final canTurnOn = status != null && blocker == null;

    return SwitchListTile(
      secondary: const Icon(Icons.gpp_good_outlined),
      title: const Text('Confirmed people only'),
      subtitle: Text(
        on || blocker == null
            ? 'Only people you have confirmed, and your approved devices, can '
                  'read what you send from this device'
            : blocker,
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
