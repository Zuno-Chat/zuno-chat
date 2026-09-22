import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/new_device_alert.dart';
import '../../../core/security/new_device_alert_provider.dart';
import '../../../core/security/security_emphasis.dart';
import '../../settings/presentation/active_sessions_page.dart';

class NewDeviceAlertBanner extends ConsumerWidget {
  const NewDeviceAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(newDeviceAlertProvider);
    if (alerts.isEmpty) return const SizedBox.shrink();

    final alert = alerts.first;
    final text = newDeviceNotificationText(alert);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      key: const ValueKey('newDeviceAlertBanner'),
      color: colors.errorContainer,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AttentionStripe(),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ActiveSessionsPage()),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      Icon(attentionIcon, color: colors.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text.title,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onErrorContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              text.body,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onErrorContainer,
                              ),
                            ),
                            if (alerts.length > 1)
                              Text(
                                '+${alerts.length - 1} more new sign-in'
                                '${alerts.length > 2 ? 's' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onErrorContainer,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: colors.onErrorContainer),
                        tooltip: 'Dismiss',
                        onPressed: () => ref
                            .read(newDeviceAlertProvider.notifier)
                            .dismiss(alert),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
