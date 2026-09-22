import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/background_sync_service.dart';
import '../../../core/notifications/delivery_auto_fallback.dart';
import '../../../core/notifications/delivery_failure.dart';
import '../../../core/notifications/delivery_failure_provider.dart';
import '../../../core/notifications/fcm_delivery_provider.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/push/play_services.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../settings/presentation/notification_delivery_page.dart';

class NotificationDeliveryBanner extends ConsumerWidget {
  const NotificationDeliveryBanner({super.key});

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    DeliveryFailure failure,
  ) async {
    switch (failure.action) {
      case DeliveryFailureAction.openSettings:
        await ref.read(autoSelectedDeliveryModeProvider.notifier).acknowledge();
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationDeliveryPage()),
        );
      case DeliveryFailureAction.openDistributorSettings:
        final distributor = unifiedPushDeliveryProvider.savedDistributor;
        if (distributor != null) {
          await BackgroundSyncService.instance.openAppSettings(distributor);
        }
      case DeliveryFailureAction.switchToUnifiedPush:
        await ref
            .read(notificationDeliveryModeProvider.notifier)
            .set(NotificationDeliveryMode.unifiedPush);
        await unifiedPushDeliveryProvider.discoverDistributorsIfNeeded();
      case DeliveryFailureAction.switchToBackgroundService:
        await ref
            .read(notificationDeliveryModeProvider.notifier)
            .set(NotificationDeliveryMode.backgroundService);
      case DeliveryFailureAction.fixGoogleServices:
        await PlayServicesProbe.instance.requestFix();
      case DeliveryFailureAction.retry:
        final client = ref.read(matrixClientProvider);
        switch (ref.read(notificationDeliveryModeProvider)) {
          case NotificationDeliveryMode.fcm:
            await fcmDeliveryProvider.registerNow(client);
          case NotificationDeliveryMode.unifiedPush:
            await unifiedPushDeliveryProvider.registerNow(client);
          case NotificationDeliveryMode.backgroundService:
            break;
        }
    }
  }

  void _dismiss(WidgetRef ref, DeliveryFailure failure) {
    ref.read(dismissedDeliveryFailureProvider.notifier).dismiss(failure);
    if (failure.notice) {
      ref.read(autoSelectedDeliveryModeProvider.notifier).acknowledge();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(deliveryFailureProvider);
    final dismissed = ref.watch(dismissedDeliveryFailureProvider);
    if (failure == null || deliveryFailureIsDismissed(failure, dismissed)) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final background = failure.notice
        ? colors.secondaryContainer
        : colors.errorContainer;
    final foreground = failure.notice
        ? colors.onSecondaryContainer
        : colors.onErrorContainer;

    return Material(
      key: const ValueKey('deliveryFailureBanner'),
      color: background,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!failure.notice) const AttentionStripe(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    Icon(
                      failure.notice ? Icons.info_outline : attentionIcon,
                      color: foreground,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        failure.message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _act(context, ref, failure),
                      child: Text(deliveryFailureActionLabel(failure.action)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Dismiss',
                      color: foreground,
                      onPressed: () => _dismiss(ref, failure),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
