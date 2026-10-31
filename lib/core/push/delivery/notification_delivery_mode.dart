import '../../l10n/l10n.dart';

enum NotificationDeliveryMode { fcm, unifiedPush, backgroundService, apns }

bool deliveryLogsEachPush(NotificationDeliveryMode mode) {
  return switch (mode) {
    NotificationDeliveryMode.fcm || NotificationDeliveryMode.apns => true,
    NotificationDeliveryMode.unifiedPush ||
    NotificationDeliveryMode.backgroundService => false,
  };
}

extension NotificationDeliveryModeCopy on NotificationDeliveryMode {
  String label(AppLocalizations l10n) => switch (this) {
    NotificationDeliveryMode.backgroundService =>
      l10n.notificationsModeBackgroundSync,
    NotificationDeliveryMode.fcm => l10n.notificationsModeGoogleServices,
    NotificationDeliveryMode.unifiedPush => l10n.notificationsModeUnifiedPush,
    NotificationDeliveryMode.apns => l10n.notificationsModeApplePush,
  };

  String description(AppLocalizations l10n) => switch (this) {
    NotificationDeliveryMode.backgroundService =>
      l10n.notificationsModeBackgroundSyncDescription,
    NotificationDeliveryMode.fcm => l10n.notificationsModeGoogleDescription,
    NotificationDeliveryMode.unifiedPush =>
      l10n.notificationsModeUnifiedPushDescription,
    NotificationDeliveryMode.apns => l10n.notificationsModeApplePushDescription,
  };
}
