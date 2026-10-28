import '../../l10n/l10n.dart';
import '../apns/apns_delivery_provider.dart';
import '../fcm/fcm_delivery_provider.dart';
import '../ring/ring_registration.dart';
import '../unified_push/unified_push_delivery_provider.dart';
import '../unified_push/unified_push_distributor_names.dart';
import 'notification_delivery_mode.dart';

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

enum DeliveryFailureReason {
  autoSelected,
  distributorBattery,
  callsSetup,
  notRegistered,
  setupFailed,
  playServicesMissing,
  playServicesNeedsUpdate,
  playServicesTurnedOff,
  googleServicesNotIncluded,
  mayNotReach,
  noDistributorFound,
  distributorRefused,
}

class DeliveryFailure {
  final DeliveryFailureReason reason;
  final String? detail;
  final DeliveryFailureAction action;
  final bool notice;

  const DeliveryFailure({
    required this.reason,
    this.detail,
    required this.action,
    this.notice = false,
  });

  String message(AppLocalizations l10n) => switch (reason) {
    DeliveryFailureReason.autoSelected => l10n.notificationsFailureAutoSelected(
      detail ?? '',
    ),
    DeliveryFailureReason.distributorBattery =>
      detail == null
          ? l10n.notificationsFailureDistributorBatteryUnnamed
          : l10n.notificationsFailureDistributorBattery(
              unifiedPushDistributorDisplayName(detail!),
            ),
    DeliveryFailureReason.callsSetup => l10n.notificationsFailureCallsSetup,
    DeliveryFailureReason.notRegistered =>
      l10n.notificationsFailureNotRegistered,
    DeliveryFailureReason.setupFailed => l10n.pushSetupFailed,
    DeliveryFailureReason.playServicesMissing => l10n.pushPlayServicesMissing,
    DeliveryFailureReason.playServicesNeedsUpdate =>
      l10n.pushPlayServicesNeedsUpdate,
    DeliveryFailureReason.playServicesTurnedOff =>
      l10n.pushPlayServicesTurnedOff,
    DeliveryFailureReason.googleServicesNotIncluded =>
      l10n.pushGoogleServicesNotIncluded,
    DeliveryFailureReason.mayNotReach => l10n.notificationsFailureMayNotReach,
    DeliveryFailureReason.noDistributorFound => l10n.pushNoDistributorFound,
    DeliveryFailureReason.distributorRefused => l10n.pushDistributorRefused,
  };

  @override
  bool operator ==(Object other) =>
      other is DeliveryFailure &&
      other.reason == reason &&
      other.detail == detail &&
      other.action == action &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(reason, detail, action, notice);
}

String deliveryFailureActionLabel(
  AppLocalizations l10n,
  DeliveryFailureAction action,
) {
  return switch (action) {
    DeliveryFailureAction.switchToUnifiedPush =>
      l10n.notificationsActionSwitchToUnifiedPush,
    DeliveryFailureAction.updatePlayServices =>
      l10n.notificationsActionUpdatePlayServices,
    DeliveryFailureAction.turnOnPlayServices =>
      l10n.notificationsActionTurnOnPlayServices,
    DeliveryFailureAction.switchToBackgroundService =>
      l10n.notificationsActionUseBackgroundSync,
    DeliveryFailureAction.retry ||
    DeliveryFailureAction.retryCalls => l10n.commonRetry,
    DeliveryFailureAction.openDistributorSettings ||
    DeliveryFailureAction.openSettings => l10n.commonOpenSettings,
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
      reason: DeliveryFailureReason.autoSelected,
      detail: mode.name,
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
  return DeliveryFailure(
    reason: DeliveryFailureReason.distributorBattery,
    detail: distributor,
    action: DeliveryFailureAction.openDistributorSettings,
  );
}

const callsSetupFailed = DeliveryFailure(
  reason: DeliveryFailureReason.callsSetup,
  action: DeliveryFailureAction.retryCalls,
);

DeliveryFailure? callsDeliveryFailure(RingRegistrationState state) =>
    state == RingRegistrationState.failed ? callsSetupFailed : null;

const _notRegistered = DeliveryFailure(
  reason: DeliveryFailureReason.notRegistered,
  action: DeliveryFailureAction.retry,
);

const _setupFailed = DeliveryFailure(
  reason: DeliveryFailureReason.setupFailed,
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
      reason: DeliveryFailureReason.playServicesMissing,
      action: switchAway,
    ),
    FcmStatus.playServicesUpdateRequired => const DeliveryFailure(
      reason: DeliveryFailureReason.playServicesNeedsUpdate,
      action: DeliveryFailureAction.updatePlayServices,
    ),
    FcmStatus.playServicesDisabled => const DeliveryFailure(
      reason: DeliveryFailureReason.playServicesTurnedOff,
      action: DeliveryFailureAction.turnOnPlayServices,
    ),
    FcmStatus.notConfigured => DeliveryFailure(
      reason: DeliveryFailureReason.googleServicesNotIncluded,
      action: switchAway,
    ),
    FcmStatus.tokenFailed || FcmStatus.pusherFailed => _setupFailed,
  };
}

DeliveryFailure? _apnsFailure(ApnsStatus status, {required int dropped}) {
  return switch (status) {
    ApnsStatus.ready when dropped > 0 => const DeliveryFailure(
      reason: DeliveryFailureReason.mayNotReach,
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
      reason: DeliveryFailureReason.noDistributorFound,
      action: DeliveryFailureAction.switchToBackgroundService,
    ),
    UnifiedPushStatus.registrationFailed => const DeliveryFailure(
      reason: DeliveryFailureReason.distributorRefused,
      action: DeliveryFailureAction.retry,
    ),
    UnifiedPushStatus.pusherFailed => _setupFailed,
  };
}
