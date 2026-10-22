import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/notifications/settings/notification_preview.dart';
import '../../../core/settings/app_preferences_provider.dart';

class NotificationPreviewOptions extends ConsumerStatefulWidget {
  const NotificationPreviewOptions({super.key});

  @override
  ConsumerState<NotificationPreviewOptions> createState() =>
      _NotificationPreviewOptionsState();
}

class _NotificationPreviewOptionsState
    extends ConsumerState<NotificationPreviewOptions> {
  Future<void> _set(NotificationPreview level) async {
    await ref.read(notificationPreviewProvider.notifier).set(level);
    await _finishHint();
  }

  Future<void> _finishHint() async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(notificationPreviewHintKey, true);
    if (mounted) setState(() {});
  }

  bool _hintDue(NotificationPreview preview) =>
      preview == NotificationPreview.full &&
      ref.watch(notificationRetentionUnpatchedProvider) &&
      ref.read(sharedPreferencesProvider).getBool(notificationPreviewHintKey) !=
          true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = ref.watch(notificationPreviewProvider);
    return RadioGroup<NotificationPreview>(
      groupValue: preview,
      onChanged: (level) => _set(level!),
      child: Column(
        children: [
          for (final level in NotificationPreview.values)
            RadioListTile<NotificationPreview>(
              title: Text(level.label(l10n)),
              subtitle: Text(level.description(l10n)),
              value: level,
            ),
          if (_hintDue(preview))
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.notificationsRetentionTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.notificationsRetentionHint),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _set(NotificationPreview.nameOnly),
                        child: Text(l10n.notificationsUseNameOnly),
                      ),
                      TextButton(
                        onPressed: _finishHint,
                        child: Text(l10n.notificationsKeepAsIs),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
