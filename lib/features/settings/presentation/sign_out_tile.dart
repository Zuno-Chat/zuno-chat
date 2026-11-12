import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/account/sign_out.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/danger_tile.dart';
import 'secure_backup_page.dart';

class SignOutTile extends ConsumerWidget {
  const SignOutTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DangerTile(
      icon: Icons.logout_outlined,
      label: context.l10n.settingsSignOut,
      onTap: () => _confirm(context, ref),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final noRecovery =
        ref.read(accountSecurityStatusProvider).value ==
        AccountSecurityStatus.noRecovery;
    final navigator = Navigator.of(context);
    final l10n = context.l10n;

    final choice = await showDialog<_SignOutChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsPageSignOutTitle),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        content: Text(
          noRecovery
              ? l10n.settingsPageSignOutBodyNoRecovery
              : l10n.settingsPageSignOutBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          if (noRecovery)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_SignOutChoice.setUpRecovery),
              child: Text(l10n.securitySetUpRecovery),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_SignOutChoice.signOut),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(
              noRecovery
                  ? l10n.settingsPageSignOutAnyway
                  : l10n.settingsSignOut,
            ),
          ),
        ],
      ),
    );

    switch (choice) {
      case null:
        return;
      case _SignOutChoice.setUpRecovery:
        await navigator.push(
          MaterialPageRoute(builder: (_) => const SecureBackupPage()),
        );
      case _SignOutChoice.signOut:
        if (context.mounted) await signOutThisDeviceOrExplain(context, ref);
    }
  }
}

enum _SignOutChoice { setUpRecovery, signOut }
