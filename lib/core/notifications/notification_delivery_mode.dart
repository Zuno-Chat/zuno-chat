enum NotificationDeliveryMode { fcm, unifiedPush, backgroundService }

bool deliveryDependsOnBatteryExemption(NotificationDeliveryMode mode) {
  return switch (mode) {
    NotificationDeliveryMode.unifiedPush ||
    NotificationDeliveryMode.backgroundService => true,
    NotificationDeliveryMode.fcm => false,
  };
}

extension NotificationDeliveryModeCopy on NotificationDeliveryMode {
  String get label => switch (this) {
    NotificationDeliveryMode.backgroundService => 'Background sync',
    NotificationDeliveryMode.fcm => 'Google services',
    NotificationDeliveryMode.unifiedPush => 'UnifiedPush',
  };

  String get description => switch (this) {
    NotificationDeliveryMode.backgroundService =>
      'No Google services or setup needed. Keeps a quiet notification showing.',
    NotificationDeliveryMode.fcm =>
      'Instant, and works on most devices with no setup',
    NotificationDeliveryMode.unifiedPush =>
      'Instant, without Google. Needs a distributor app such as ntfy.',
  };
}
