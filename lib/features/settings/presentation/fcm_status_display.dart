import '../../../core/l10n/l10n.dart';
import '../../../core/push/delivery/delivery_failure.dart';
import '../../../core/push/fcm/fcm_delivery_provider.dart';

enum PushStatusAction { none, register, retry, fix }

PushStatusAction fcmStatusAction(FcmStatus status) {
  switch (status) {
    case FcmStatus.checkingPlayServices:
    case FcmStatus.registering:
    case FcmStatus.postingPusher:
    case FcmStatus.playServicesUnavailable:
    case FcmStatus.notConfigured:
    case FcmStatus.ready:
      return PushStatusAction.none;
    case FcmStatus.idle:
      return PushStatusAction.register;
    case FcmStatus.tokenFailed:
    case FcmStatus.pusherFailed:
      return PushStatusAction.retry;
    case FcmStatus.playServicesUpdateRequired:
    case FcmStatus.playServicesDisabled:
      return PushStatusAction.fix;
  }
}

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

bool fcmStatusIsBusy(FcmStatus status) {
  switch (status) {
    case FcmStatus.checkingPlayServices:
    case FcmStatus.registering:
    case FcmStatus.postingPusher:
      return true;
    case FcmStatus.idle:
    case FcmStatus.playServicesUnavailable:
    case FcmStatus.playServicesUpdateRequired:
    case FcmStatus.playServicesDisabled:
    case FcmStatus.notConfigured:
    case FcmStatus.tokenFailed:
    case FcmStatus.ready:
    case FcmStatus.pusherFailed:
      return false;
  }
}

String fcmStatusLabel(AppLocalizations l10n, FcmStatus status) {
  switch (status) {
    case FcmStatus.idle:
      return l10n.pushInactive;
    case FcmStatus.checkingPlayServices:
      return l10n.pushCheckingDevice;
    case FcmStatus.playServicesUnavailable:
      return l10n.pushPlayServicesMissing;
    case FcmStatus.playServicesUpdateRequired:
      return l10n.pushPlayServicesNeedsUpdate;
    case FcmStatus.playServicesDisabled:
      return l10n.pushPlayServicesTurnedOff;
    case FcmStatus.notConfigured:
      return l10n.pushGoogleServicesNotIncluded;
    case FcmStatus.registering:
      return l10n.pushRegistering;
    case FcmStatus.tokenFailed:
      return l10n.pushSetupFailed;
    case FcmStatus.postingPusher:
      return l10n.pushFinishingRegistration;
    case FcmStatus.ready:
      return l10n.pushActive;
    case FcmStatus.pusherFailed:
      return l10n.pushCouldNotFinishRegistration;
  }
}
