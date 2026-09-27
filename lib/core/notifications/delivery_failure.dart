import '../push/unified_push_distributor_names.dart';
import 'apns_delivery_provider.dart';
import 'fcm_delivery_provider.dart';
import 'notification_delivery_mode.dart';
import 'unified_push_delivery_provider.dart';

enum DeliveryFailureAction {
  switchToUnifiedPush,
  fixGoogleServices,
  switchToBackgroundService,
  retry,
  openDistributorSettings,
  openSettings,
}

class DeliveryFailure {
  final String message;
  final DeliveryFailureAction action;
  final bool notice;

  const DeliveryFailure({
    required this.message,
    required this.action,
    this.notice = false,
  });
}

String deliveryFailureActionLabel(DeliveryFailureAction action) {
  return switch (action) {
    DeliveryFailureAction.switchToUnifiedPush => 'Switch to UnifiedPush',
    DeliveryFailureAction.fixGoogleServices => 'Fix Google services',
    DeliveryFailureAction.switchToBackgroundService => 'Use background sync',
    DeliveryFailureAction.retry => 'Retry',
    DeliveryFailureAction.openDistributorSettings => 'Open settings',
    DeliveryFailureAction.openSettings => 'Open settings',
  };
}

DeliveryFailure? notificationDeliveryFailure({
  required NotificationDeliveryMode mode,
  required FcmStatus fcm,
  required UnifiedPushStatus unifiedPush,
  required ApnsStatus apns,
  int apnsDropped = 0,
  bool distributorBatteryRestricted = false,
  String? distributor,
  NotificationDeliveryMode? autoSelected,
}) {
  final failure = switch (mode) {
    NotificationDeliveryMode.fcm => _fcmFailure(fcm),
    NotificationDeliveryMode.unifiedPush =>
      _unifiedPushFailure(unifiedPush) ??
          _distributorBatteryFailure(
            unifiedPush,
            restricted: distributorBatteryRestricted,
            distributor: distributor,
          ),
    NotificationDeliveryMode.apns => _apnsFailure(apns, dropped: apnsDropped),
    NotificationDeliveryMode.backgroundService => null,
  };
  if (failure != null) return failure;
  if (autoSelected != null && autoSelected == mode) {
    return DeliveryFailure(
      message:
          'No Google services on this device, so notifications use '
          '${mode.label}',
      action: DeliveryFailureAction.openSettings,
      notice: true,
    );
  }
  return null;
}

DeliveryFailure? _distributorBatteryFailure(
  UnifiedPushStatus status, {
  required bool restricted,
  required String? distributor,
}) {
  if (!restricted || status != UnifiedPushStatus.ready) return null;
  final name = distributor == null
      ? 'Your distributor app'
      : unifiedPushDistributorDisplayName(distributor);
  return DeliveryFailure(
    message: '$name is battery restricted, so notifications can arrive late',
    action: DeliveryFailureAction.openDistributorSettings,
  );
}

DeliveryFailure? _fcmFailure(FcmStatus status) {
  return switch (status) {
    FcmStatus.idle ||
    FcmStatus.checkingPlayServices ||
    FcmStatus.registering ||
    FcmStatus.postingPusher ||
    FcmStatus.ready => null,
    FcmStatus.playServicesUnavailable => const DeliveryFailure(
      message: 'This device does not have Google services',
      action: DeliveryFailureAction.switchToUnifiedPush,
    ),
    FcmStatus.playServicesUpdateRequired => const DeliveryFailure(
      message: 'Google services needs an update',
      action: DeliveryFailureAction.fixGoogleServices,
    ),
    FcmStatus.tokenFailed => const DeliveryFailure(
      message: 'Could not set up notifications on this device',
      action: DeliveryFailureAction.retry,
    ),
    FcmStatus.pusherFailed => const DeliveryFailure(
      message: 'The server did not accept this device',
      action: DeliveryFailureAction.retry,
    ),
  };
}

DeliveryFailure? _apnsFailure(ApnsStatus status, {required int dropped}) {
  return switch (status) {
    ApnsStatus.ready when dropped > 0 => const DeliveryFailure(
      message:
          'The server dropped this device, so notifications may not arrive',
      action: DeliveryFailureAction.retry,
    ),
    ApnsStatus.idle ||
    ApnsStatus.registering ||
    ApnsStatus.postingPusher ||
    ApnsStatus.ready => null,
    ApnsStatus.tokenFailed => const DeliveryFailure(
      message: 'Could not set up notifications on this device',
      action: DeliveryFailureAction.retry,
    ),
    ApnsStatus.pusherFailed => const DeliveryFailure(
      message: 'The server did not accept this device',
      action: DeliveryFailureAction.retry,
    ),
  };
}

DeliveryFailure? _unifiedPushFailure(UnifiedPushStatus status) {
  return switch (status) {
    UnifiedPushStatus.idle ||
    UnifiedPushStatus.findingDistributor ||
    UnifiedPushStatus.distributorSelected ||
    UnifiedPushStatus.registering ||
    UnifiedPushStatus.postingPusher ||
    UnifiedPushStatus.ready => null,
    UnifiedPushStatus.noDistributorFound => const DeliveryFailure(
      message: 'No distributor app on this device to deliver through',
      action: DeliveryFailureAction.switchToBackgroundService,
    ),
    UnifiedPushStatus.registrationFailed => const DeliveryFailure(
      message: 'The distributor app refused to register this device',
      action: DeliveryFailureAction.retry,
    ),
    UnifiedPushStatus.pusherFailed => const DeliveryFailure(
      message: 'The server did not accept this device',
      action: DeliveryFailureAction.retry,
    ),
  };
}
