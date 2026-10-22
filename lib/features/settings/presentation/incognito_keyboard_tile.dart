import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/settings/app_preferences_provider.dart';

class IncognitoKeyboardTile extends ConsumerWidget {
  const IncognitoKeyboardTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(platformCapabilitiesProvider);
    if (!capabilities.incognitoKeyboard) return const SizedBox.shrink();
    final l10n = context.l10n;
    return SwitchListTile(
      secondary: const Icon(Icons.keyboard_alt_outlined),
      title: Text(l10n.settingsSecurityIncognitoKeyboard),
      subtitle: Text(
        capabilities.keyboardLearningOptOut
            ? l10n.settingsSecurityIncognitoKeyboardSubtitle
            : l10n.settingsSecurityIncognitoKeyboardAppleOnlySubtitle,
      ),
      value: ref.watch(incognitoKeyboardProvider),
      onChanged: (value) =>
          ref.read(incognitoKeyboardProvider.notifier).set(value),
    );
  }
}
