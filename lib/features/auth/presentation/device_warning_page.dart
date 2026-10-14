import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/security/device_safety.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';

class DeviceWarningPage extends StatelessWidget {
  final Set<DeviceRisk> risks;
  final VoidCallback onContinue;

  const DeviceWarningPage({
    required this.risks,
    required this.onContinue,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: StepLayout(
          hero: const StepHero(icon: Icons.gpp_maybe_outlined),
          title: l10n.authDeviceWarningTitle,
          body: l10n.authDeviceWarningBody,
          actions: [
            FilledButton(
              onPressed: onContinue,
              child: Text(l10n.commonContinueAnyway),
            ),
          ],
          children: [
            for (final risk in DeviceRisk.values)
              if (risks.contains(risk)) _RiskRow(risk: risk),
            const SizedBox(height: 8),
            Text(
              l10n.authDeviceWarningAdvice,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final DeviceRisk risk;

  const _RiskRow({required this.risk});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, title, detail) = switch (risk) {
      DeviceRisk.unlockedBootloader => (
        Icons.lock_open_outlined,
        l10n.authDeviceRiskBootloaderTitle,
        l10n.authDeviceRiskBootloaderDetail,
      ),
      DeviceRisk.rooted => (
        Icons.admin_panel_settings_outlined,
        l10n.authDeviceRiskRootedTitle,
        l10n.authDeviceRiskRootedDetail,
      ),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
    );
  }
}
