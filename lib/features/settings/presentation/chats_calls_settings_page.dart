import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

class ChatsCallsSettingsPage extends ConsumerWidget {
  const ChatsCallsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final sendTypingIndicator = ref.watch(sendTypingIndicatorProvider);
    final confirmBeforeCalling = ref.watch(confirmBeforeCallingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats & calls')),
      body: CardListView(
        children: [
          CardGroup(
            title: 'Appearance',
            children: [
              RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (mode) =>
                    ref.read(themeModeProvider.notifier).set(mode!),
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('Follow system'),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Light'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Dark'),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
            ],
          ),
          CardGroup(
            title: 'Chats',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.more_horiz_outlined),
                title: const Text('Show when you are typing'),
                subtitle: const Text('You still see when others are typing'),
                value: sendTypingIndicator,
                onChanged: (value) =>
                    ref.read(sendTypingIndicatorProvider.notifier).set(value),
              ),
            ],
          ),
          CardGroup(
            title: 'Calls',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.shield_moon_outlined),
                title: const Text('Prevent accidental calls'),
                subtitle: const Text(
                  'Asks before starting a voice or video call',
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
