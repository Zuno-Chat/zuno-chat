import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../blocking/presentation/blocked_people_page.dart';
import '../../verification/presentation/approve_this_device_page.dart';
import 'active_sessions_page.dart';
import 'secure_backup_page.dart';
import 'security_status_card.dart';
import 'settings_widgets.dart';
import 'why_security_page.dart';

class SecurityPrivacySettingsPage extends ConsumerStatefulWidget {
  const SecurityPrivacySettingsPage({super.key});

  @override
  ConsumerState<SecurityPrivacySettingsPage> createState() =>
      _SecurityPrivacySettingsPageState();
}

class _SecurityPrivacySettingsPageState
    extends ConsumerState<SecurityPrivacySettingsPage> {
  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) ref.invalidate(accountSecurityFactsProvider);
  }

  void _handleStatusAction(AccountSecurityStatus status) {
    switch (status) {
      case AccountSecurityStatus.noRecovery:
        _push(const SecureBackupPage());
      case AccountSecurityStatus.deviceLocked:
        _push(const ApproveThisDevicePage());
      case AccountSecurityStatus.deviceWaiting:
        _push(const ActiveSessionsPage());
      case AccountSecurityStatus.recoveryStale:
        _push(const SecureBackupPage(autoRestoreExisting: true));
      case AccountSecurityStatus.protected:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final incognitoKeyboard = ref.watch(incognitoKeyboardProvider);
    final preventScreenshots = ref.watch(preventScreenshotsProvider);
    final status = ref.watch(accountSecurityStatusProvider).value;
    final hasRecovery =
        status != null && status != AccountSecurityStatus.noRecovery;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: CardListView(
        children: [
          SecurityStatusCard(onAction: _handleStatusAction),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(
                  hasRecovery ? 'Change your recovery code' : 'Set up recovery',
                ),
                subtitle: Text(
                  hasRecovery
                      ? 'Replaces the current one. Your other devices will '
                            'need approving again.'
                      : 'Twelve words that bring your messages back on a new '
                            'device',
                ),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => _push(const SecureBackupPage()),
              ),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Your devices'),
                subtitle: const Text(
                  'See what is signed in, and sign things out',
                ),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => _push(const ActiveSessionsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined),
                title: const Text('Blocked people'),
                subtitle: const Text(
                  'People whose messages and invitations do not reach you',
                ),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => _push(const BlockedPeoplePage()),
              ),
            ],
          ),
          CardGroup(
            title: 'On this device',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.keyboard_alt_outlined),
                title: const Text('Incognito keyboard'),
                subtitle: const Text(
                  'Asks the keyboard not to learn from what you type',
                ),
                value: incognitoKeyboard,
                onChanged: (value) =>
                    ref.read(incognitoKeyboardProvider.notifier).set(value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.screenshot_outlined),
                title: const Text('Prevent screenshots'),
                subtitle: const Text(
                  'Blocks screenshots and screen recording, and hides Zuno in '
                  'the recent apps preview',
                ),
                value: preventScreenshots,
                onChanged: (value) =>
                    ref.read(preventScreenshotsProvider.notifier).set(value),
              ),
            ],
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('How this works'),
                subtitle: const Text('Recovery, devices and confirming people'),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => _push(const WhySecurityPage()),
              ),
              const ComingSoonTile(
                icon: Icons.tune_outlined,
                title: 'Advanced',
                subtitle: 'Keys, secret storage, key backup',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
