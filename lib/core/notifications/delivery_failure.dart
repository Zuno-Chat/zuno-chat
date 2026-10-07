import '../push/unified_push_distributor_names.dart';
import '../push/voip/voip_registration.dart';
import 'apns_delivery_provider.dart';
import 'fcm_delivery_provider.dart';
import 'notification_delivery_mode.dart';
import 'unified_push_delivery_provider.dart';

enum DeliveryFailureAction {
  switchToUnifiedPush,
  updatePlayServices,
  turnOnPlayServices,
  switchToBackgroundService,
  retry,
  retryCalls,
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
    DeliveryFailureAction.updatePlayServices => 'Update Google Play services',
    DeliveryFailureAction.turnOnPlayServices => 'Turn on Google Play services',
    DeliveryFailureAction.switchToBackgroundService => 'Use background sync',
    DeliveryFailureAction.retry || DeliveryFailureAction.retryCalls => 'Retry',
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
  bool? distributorInstalled,
  NotificationDeliveryMode? autoSelected,
  bool fcmRemoved = false,
  bool unifiedPushRemoved = false,
}) {
  final failure = switch (mode) {
    NotificationDeliveryMode.fcm => _fcmFailure(
      fcm,
      distributorInstalled: distributorInstalled,
      removed: fcmRemoved,
    ),
    NotificationDeliveryMode.unifiedPush =>
      _unifiedPushFailure(unifiedPush, removed: unifiedPushRemoved) ??
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
          'Google services cannot be used, so notifications use '
          '${_midSentence(mode)}',
      action: DeliveryFailureAction.openSettings,
      notice: true,
    );
  }
  return null;
}

String _midSentence(NotificationDeliveryMode mode) => switch (mode) {
  NotificationDeliveryMode.backgroundService => 'background sync',
  NotificationDeliveryMode.fcm ||
  NotificationDeliveryMode.unifiedPush ||
  NotificationDeliveryMode.apns => mode.label,
};

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

const callsSetupFailed = DeliveryFailure(
  message: 'Could not set up calls to ring while Zuno is closed',
  action: DeliveryFailureAction.retryCalls,
);

DeliveryFailure? callsDeliveryFailure(VoipRegistrationState state) =>
    state == VoipRegistrationState.failed ? callsSetupFailed : null;

const _notRegistered = DeliveryFailure(
  message: 'This device is not registered for notifications',
  action: DeliveryFailureAction.retry,
);

const _setupFailed = DeliveryFailure(
  message: 'Could not set up notifications on this device',
  action: DeliveryFailureAction.retry,
);

DeliveryFailure? _fcmFailure(
  FcmStatus status, {
  required bool? distributorInstalled,
  required bool removed,
}) {
  final switchAway = distributorInstalled == false
      ? DeliveryFailureAction.switchToBackgroundService
      : DeliveryFailureAction.switchToUnifiedPush;
  return switch (status) {
    FcmStatus.idle when removed => _notRegistered,
    FcmStatus.idle ||
    FcmStatus.checkingPlayServices ||
    FcmStatus.registering ||
    FcmStatus.postingPusher ||
    FcmStatus.ready => null,
    FcmStatus.playServicesUnavailable => DeliveryFailure(
      message: 'This device does not have Google Play services',
      action: switchAway,
    ),
    FcmStatus.playServicesUpdateRequired => const DeliveryFailure(
      message: 'Google Play services needs an update',
      action: DeliveryFailureAction.updatePlayServices,
    ),
    FcmStatus.playServicesDisabled => const DeliveryFailure(
      message: 'Google Play services is turned off',
      action: DeliveryFailureAction.turnOnPlayServices,
    ),
    FcmStatus.notConfigured => DeliveryFailure(
      message: 'This version of Zuno does not include Google services',
      action: switchAway,
    ),
    FcmStatus.tokenFailed || FcmStatus.pusherFailed => _setupFailed,
  };
}

DeliveryFailure? _apnsFailure(ApnsStatus status, {required int dropped}) {
  return switch (status) {
    ApnsStatus.ready when dropped > 0 => const DeliveryFailure(
      message: 'Notifications may not reach this device',
      action: DeliveryFailureAction.retry,
    ),
    ApnsStatus.idle ||
    ApnsStatus.registering ||
    ApnsStatus.postingPusher ||
    ApnsStatus.ready => null,
    ApnsStatus.tokenFailed || ApnsStatus.pusherFailed => _setupFailed,
  };
}

DeliveryFailure? _unifiedPushFailure(
  UnifiedPushStatus status, {
  required bool removed,
}) {
  return switch (status) {
    UnifiedPushStatus.idle ||
    UnifiedPushStatus.distributorSelected when removed => _notRegistered,
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
    UnifiedPushStatus.pusherFailed => _setupFailed,
  };
}
