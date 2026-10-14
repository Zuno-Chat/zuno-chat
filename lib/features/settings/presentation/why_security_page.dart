import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/settings/app_preferences_provider.dart';

class WhySecurityPage extends StatelessWidget {
  final UrlOpener openUrl;

  const WhySecurityPage({this.openUrl = openExternally, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget para(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsWhyTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          para(l10n.settingsWhyIntroEncrypted),
          para(l10n.settingsWhyIntroLimits),
          heading(l10n.settingsWhyRecoveryHeading),
          para(l10n.settingsWhyRecoveryLocked),
          para(l10n.settingsWhyRecoveryWay),
          heading(l10n.settingsWhyApprovalHeading),
          para(l10n.settingsWhyApprovalStranger),
          para(l10n.settingsWhyApprovalDeliberate),
          heading(l10n.settingsWhyConfirmingHeading),
          para(l10n.settingsWhyConfirmingServer),
          para(l10n.settingsWhyConfirmingHow),
          if (confirmedPeopleOnlyOffered) ...[
            heading(l10n.settingsWhyConfirmedOnlyHeading),
            para(l10n.settingsWhyConfirmedOnlyNormally),
            para(l10n.settingsWhyConfirmedOnlyTurnOn),
          ],
          heading(l10n.settingsWhyInterruptsHeading),
          para(l10n.settingsWhyInterruptsBody),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_outlined),
            title: Text(l10n.settingsWhyAllProtections),
            subtitle: Text('${securityUri.host}${securityUri.path}'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openLink(context, securityUri, openUrl: openUrl),
          ),
        ],
      ),
    );
  }
}
