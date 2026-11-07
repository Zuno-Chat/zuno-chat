import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/client/matrix_client_provider.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'matrix_logo_icon.dart';

class ChatsCallsSettingsPage extends ConsumerWidget {
  const ChatsCallsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final themeMode = ref.watch(themeModeProvider);
    final sendTypingIndicator = ref.watch(sendTypingIndicatorProvider);
    final confirmBeforeCalling = ref.watch(confirmBeforeCallingProvider);
    final matrixExperience = ref.watch(matrixExperienceProvider);
    final userId = ref.watch(matrixClientProvider).userID ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsChatsCallsTitle)),
      body: CardListView(
        children: [
          CardGroup(
            title: l10n.settingsChatsCallsAppearance,
            children: [
              RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (mode) =>
                    ref.read(themeModeProvider.notifier).set(mode!),
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text(l10n.settingsChatsCallsFollowSystem),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text(l10n.settingsChatsCallsLight),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text(l10n.settingsChatsCallsDark),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
            ],
          ),
          CardGroup(
            title: l10n.settingsChatsCallsChats,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.more_horiz_outlined),
                title: Text(l10n.settingsChatsCallsTyping),
                subtitle: Text(l10n.settingsChatsCallsTypingSubtitle),
                value: sendTypingIndicator,
                onChanged: (value) =>
                    ref.read(sendTypingIndicatorProvider.notifier).set(value),
              ),
              SwitchListTile(
                secondary: const MatrixLogoIcon(),
                title: Text(l10n.settingsChatsCallsMatrixExperience),
                subtitle: Text(
                  l10n.settingsChatsCallsMatrixExperienceSubtitle(userId),
                ),
                value: matrixExperience,
                onChanged: (value) =>
                    ref.read(matrixExperienceProvider.notifier).set(value),
              ),
            ],
          ),
          CardGroup(
            title: l10n.settingsChatsCallsCalls,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.shield_moon_outlined),
                title: Text(l10n.settingsChatsCallsPreventAccidental),
                subtitle: Text(
                  l10n.settingsChatsCallsPreventAccidentalSubtitle,
                ),
                value: confirmBeforeCalling,
                onChanged: (value) =>
                    ref.read(confirmBeforeCallingProvider.notifier).set(value),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
