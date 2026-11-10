import '../../l10n/l10n.dart';
import '../delivery/delivery_failure.dart';
import '../delivery/push_status_action.dart';
import 'fcm_delivery_provider.dart';

PushStatusAction fcmStatusAction(FcmStatus status) => switch (status) {
  FcmStatus.checkingPlayServices ||
  FcmStatus.registering ||
  FcmStatus.postingPusher ||
  FcmStatus.playServicesUnavailable ||
  FcmStatus.notConfigured ||
  FcmStatus.ready => PushStatusAction.none,
  FcmStatus.idle => PushStatusAction.register,
  FcmStatus.tokenFailed || FcmStatus.pusherFailed => PushStatusAction.retry,
  FcmStatus.playServicesUpdateRequired ||
  FcmStatus.playServicesDisabled => PushStatusAction.fix,
};

String? fcmFixLabel(AppLocalizations l10n, FcmStatus status) =>
    switch (status) {
      FcmStatus.playServicesUpdateRequired => deliveryFailureActionLabel(
        l10n,
        DeliveryFailureAction.updatePlayServices,
      ),
      FcmStatus.playServicesDisabled => deliveryFailureActionLabel(
        l10n,
        DeliveryFailureAction.turnOnPlayServices,
      ),
      _ => null,
    };

bool fcmStatusIsBusy(FcmStatus status) => switch (status) {
  FcmStatus.checkingPlayServices ||
  FcmStatus.registering ||
  FcmStatus.postingPusher => true,
  FcmStatus.idle ||
  FcmStatus.playServicesUnavailable ||
  FcmStatus.playServicesUpdateRequired ||
  FcmStatus.playServicesDisabled ||
  FcmStatus.notConfigured ||
  FcmStatus.tokenFailed ||
  FcmStatus.ready ||
  FcmStatus.pusherFailed => false,
};

String fcmStatusLabel(AppLocalizations l10n, FcmStatus status) =>
    switch (status) {
      FcmStatus.idle => l10n.pushInactive,
      FcmStatus.checkingPlayServices => l10n.pushCheckingDevice,
      FcmStatus.playServicesUnavailable => l10n.pushPlayServicesMissing,
      FcmStatus.playServicesUpdateRequired => l10n.pushPlayServicesNeedsUpdate,
      FcmStatus.playServicesDisabled => l10n.pushPlayServicesTurnedOff,
      FcmStatus.notConfigured => l10n.pushGoogleServicesNotIncluded,
      FcmStatus.registering => l10n.pushRegistering,
      FcmStatus.tokenFailed => l10n.pushSetupFailed,
      FcmStatus.postingPusher => l10n.pushFinishingRegistration,
      FcmStatus.ready => l10n.pushActive,
      FcmStatus.pusherFailed => l10n.pushCouldNotFinishRegistration,
    };
