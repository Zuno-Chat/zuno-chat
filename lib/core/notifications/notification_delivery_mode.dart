enum NotificationDeliveryMode { fcm, unifiedPush, backgroundService, apns }

bool deliveryDependsOnBatteryExemption(NotificationDeliveryMode mode) {
  return switch (mode) {
    NotificationDeliveryMode.unifiedPush ||
    NotificationDeliveryMode.backgroundService => true,
    NotificationDeliveryMode.fcm || NotificationDeliveryMode.apns => false,
  };
}

extension NotificationDeliveryModeCopy on NotificationDeliveryMode {
  String get label => switch (this) {
    NotificationDeliveryMode.backgroundService => 'Background sync',
    NotificationDeliveryMode.fcm => 'Google services',
    NotificationDeliveryMode.unifiedPush => 'UnifiedPush',
    NotificationDeliveryMode.apns => 'Apple push',
  };

  String get description => switch (this) {
    NotificationDeliveryMode.backgroundService =>
      'No Google services or setup needed. Keeps a quiet notification showing.',
    NotificationDeliveryMode.fcm =>
      'Instant, and works on most devices with no setup',
    NotificationDeliveryMode.unifiedPush =>
      'Instant, without Google. Needs a distributor app such as ntfy.',
    NotificationDeliveryMode.apns => 'Instant, through Apple, with no setup',
  };
}
