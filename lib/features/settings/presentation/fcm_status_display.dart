import '../../../core/notifications/fcm_delivery_provider.dart';

enum FcmStatusAction { none, register, retry, open }

FcmStatusAction fcmStatusAction(FcmStatus status) {
  switch (status) {
    case FcmStatus.checkingPlayServices:
    case FcmStatus.registering:
    case FcmStatus.postingPusher:
    case FcmStatus.playServicesUnavailable:
      return FcmStatusAction.none;
    case FcmStatus.idle:
      return FcmStatusAction.register;
    case FcmStatus.tokenFailed:
    case FcmStatus.pusherFailed:
    case FcmStatus.playServicesUpdateRequired:
      return FcmStatusAction.retry;
    case FcmStatus.ready:
      return FcmStatusAction.open;
  }
}

bool fcmStatusIsBusy(FcmStatus status) {
  switch (status) {
    case FcmStatus.checkingPlayServices:
    case FcmStatus.registering:
    case FcmStatus.postingPusher:
      return true;
    case FcmStatus.idle:
    case FcmStatus.playServicesUnavailable:
    case FcmStatus.playServicesUpdateRequired:
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
      return 'This device does not have Google services';
    case FcmStatus.playServicesUpdateRequired:
      return 'Google services needs an update';
    case FcmStatus.registering:
      return 'Registering…';
    case FcmStatus.tokenFailed:
      return 'Could not set up notifications on this device';
    case FcmStatus.postingPusher:
      return 'Registering with the server…';
    case FcmStatus.ready:
      return 'Active. Receiving notifications.';
    case FcmStatus.pusherFailed:
      return 'The server rejected the registration';
  }
}
