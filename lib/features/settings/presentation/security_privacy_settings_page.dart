import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../blocking/presentation/blocked_people_page.dart';
import 'active_sessions_page.dart';
import 'confirmed_people_only_tile.dart';
import 'secure_backup_page.dart';
import 'security_status_action.dart';
import 'security_status_card.dart';
import 'settings_widgets.dart';
import 'why_security_page.dart';

class SecurityPrivacySettingsPage extends ConsumerWidget {
  const SecurityPrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final incognitoKeyboard = ref.watch(incognitoKeyboardProvider);
    final preventScreenshots = ref.watch(preventScreenshotsProvider);
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final status = ref.watch(accountSecurityStatusProvider).value;
    final hasRecovery =
        status != null && status != AccountSecurityStatus.noRecovery;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSecurityTitle)),
      body: CardListView(
        children: [
          SecurityStatusCard(
            onAction: (status) => runSecurityStatusAction(context, ref, status),
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(
                  hasRecovery
                      ? l10n.settingsSecurityChangeRecovery
                      : l10n.securitySetUpRecovery,
                ),
                subtitle: Text(
                  hasRecovery
                      ? l10n.settingsSecurityChangeRecoverySubtitle
                      : l10n.settingsSecuritySetUpRecoverySubtitle,
                ),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () =>
                    pushSecurityPage(context, ref, const SecureBackupPage()),
              ),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(l10n.settingsSecurityYourDevices),
                subtitle: Text(l10n.settingsSecurityYourDevicesSubtitle),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () =>
                    pushSecurityPage(context, ref, const ActiveSessionsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined),
                title: Text(l10n.settingsSecurityBlockedPeople),
                subtitle: Text(l10n.settingsSecurityBlockedPeopleSubtitle),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () =>
                    pushSecurityPage(context, ref, const BlockedPeoplePage()),
              ),
            ],
          ),
          CardGroup(
            title: l10n.settingsSecurityOnThisDevice,
            children: [
              if (capabilities.keyboardLearningOptOut)
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_alt_outlined),
                  title: Text(l10n.settingsSecurityIncognitoKeyboard),
                  subtitle: Text(
                    l10n.settingsSecurityIncognitoKeyboardSubtitle,
                  ),
                  value: incognitoKeyboard,
                  onChanged: (value) =>
                      ref.read(incognitoKeyboardProvider.notifier).set(value),
                ),
              if (capabilities.screenSecurity)
                SwitchListTile(
                  secondary: const Icon(Icons.screenshot_outlined),
                  title: Text(
                    capabilities.screenshotBlocking
                        ? l10n.settingsSecurityPreventScreenshots
                        : l10n.settingsSecurityHideScreenContent,
                  ),
                  subtitle: Text(
                    capabilities.screenshotBlocking
                        ? l10n.settingsSecurityPreventScreenshotsSubtitle
                        : l10n.settingsSecurityHideScreenContentSubtitle,
                  ),
                  value: preventScreenshots,
                  onChanged: (value) =>
                      ref.read(preventScreenshotsProvider.notifier).set(value),
                ),
              if (confirmedPeopleOnlyOffered) const ConfirmedPeopleOnlyTile(),
            ],
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(l10n.settingsSecurityHowThisWorks),
                subtitle: Text(l10n.settingsSecurityHowThisWorksSubtitle),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () =>
                    pushSecurityPage(context, ref, const WhySecurityPage()),
              ),
              ComingSoonTile(
                icon: Icons.tune_outlined,
                title: l10n.settingsSecurityAdvanced,
                subtitle: l10n.settingsSecurityAdvancedSubtitle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
