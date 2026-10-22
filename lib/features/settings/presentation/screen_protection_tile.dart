import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/settings/app_preferences_provider.dart';

class ScreenProtectionTile extends ConsumerWidget {
  const ScreenProtectionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(platformCapabilitiesProvider);
    if (!capabilities.screenSecurity) return const SizedBox.shrink();
    final l10n = context.l10n;
    final blocksScreenshots = capabilities.screenshotBlocking;
    return SwitchListTile(
      secondary: const Icon(Icons.screenshot_outlined),
      title: Text(
        blocksScreenshots
            ? l10n.settingsSecurityPreventScreenshots
            : l10n.settingsSecurityHideScreenContent,
      ),
      subtitle: Text(
        blocksScreenshots
            ? l10n.settingsSecurityPreventScreenshotsSubtitle
            : l10n.settingsSecurityHideScreenContentSubtitle,
      ),
      value: ref.watch(preventScreenshotsProvider),
      onChanged: (value) =>
          ref.read(preventScreenshotsProvider.notifier).set(value),
    );
  }
}
