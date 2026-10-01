import '../../../core/notifications/delivery_failure.dart';
import '../../../core/notifications/fcm_delivery_provider.dart';

enum PushStatusAction { none, register, retry, fix, open }

PushStatusAction fcmStatusAction(FcmStatus status) {
  switch (status) {
    case FcmStatus.checkingPlayServices:
    case FcmStatus.registering:
    case FcmStatus.postingPusher:
    case FcmStatus.playServicesUnavailable:
    case FcmStatus.notConfigured:
      return PushStatusAction.none;
    case FcmStatus.idle:
      return PushStatusAction.register;
    case FcmStatus.tokenFailed:
    case FcmStatus.pusherFailed:
      return PushStatusAction.retry;
    case FcmStatus.playServicesUpdateRequired:
    case FcmStatus.playServicesDisabled:
      return PushStatusAction.fix;
    case FcmStatus.ready:
      return PushStatusAction.open;
  }
}

String? fcmFixLabel(FcmStatus status) => switch (status) {
  FcmStatus.playServicesUpdateRequired => deliveryFailureActionLabel(
    DeliveryFailureAction.updatePlayServices,
  ),
  FcmStatus.playServicesDisabled => deliveryFailureActionLabel(
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

String fcmStatusLabel(FcmStatus status) {
  switch (status) {
    case FcmStatus.idle:
      return 'Inactive';
    case FcmStatus.checkingPlayServices:
      return 'Checking this device…';
    case FcmStatus.playServicesUnavailable:
      return 'This device does not have Google Play services';
    case FcmStatus.playServicesUpdateRequired:
      return 'Google Play services needs an update';
    case FcmStatus.playServicesDisabled:
      return 'Google Play services is turned off';
    case FcmStatus.notConfigured:
      return 'This version of Zuno does not include Google services';
    case FcmStatus.registering:
      return 'Registering…';
    case FcmStatus.tokenFailed:
      return 'Could not set up notifications on this device';
    case FcmStatus.postingPusher:
      return 'Finishing registration…';
    case FcmStatus.ready:
      return 'Active. Receiving notifications.';
    case FcmStatus.pusherFailed:
      return 'Could not finish registration';
  }
}
