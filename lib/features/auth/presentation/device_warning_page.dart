import 'package:flutter/material.dart';

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
    return Scaffold(
      body: SafeArea(
        child: StepLayout(
          hero: const StepHero(icon: Icons.gpp_maybe_outlined),
          title: 'This device may not be safe',
          body:
              'Zuno encrypts your messages, but it cannot protect them from '
              'the device itself.',
          actions: [
            FilledButton(
              onPressed: onContinue,
              child: const Text('Continue anyway'),
            ),
          ],
          children: [
            for (final risk in DeviceRisk.values)
              if (risks.contains(risk)) _RiskRow(risk: risk),
            const SizedBox(height: 8),
            Text(
              'If you did not set this up yourself, someone else may have. '
              'Consider using another device.',
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
    final (icon, title, detail) = switch (risk) {
      DeviceRisk.unlockedBootloader => (
        Icons.lock_open_outlined,
        'The bootloader is unlocked',
        'The system software can be replaced without you noticing.',
      ),
      DeviceRisk.rooted => (
        Icons.admin_panel_settings_outlined,
        'This device is rooted',
        'An app with root access can read your messages and keys.',
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
