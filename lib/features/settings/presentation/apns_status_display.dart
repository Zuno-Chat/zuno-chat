import '../../../core/notifications/apns_delivery_provider.dart';
import 'fcm_status_display.dart';

PushStatusAction apnsStatusAction(ApnsStatus status) => switch (status) {
  ApnsStatus.registering || ApnsStatus.postingPusher => PushStatusAction.none,
  ApnsStatus.idle => PushStatusAction.register,
  ApnsStatus.tokenFailed || ApnsStatus.pusherFailed => PushStatusAction.retry,
  ApnsStatus.ready => PushStatusAction.open,
};

bool apnsStatusIsBusy(ApnsStatus status) => switch (status) {
  ApnsStatus.registering || ApnsStatus.postingPusher => true,
  ApnsStatus.idle ||
  ApnsStatus.tokenFailed ||
  ApnsStatus.ready ||
  ApnsStatus.pusherFailed => false,
};

String apnsStatusLabel(ApnsStatus status, {int dropped = 0}) =>
    switch (status) {
      ApnsStatus.idle => 'Inactive',
      ApnsStatus.registering => 'Registering…',
      ApnsStatus.tokenFailed => 'Could not set up notifications on this device',
      ApnsStatus.postingPusher => 'Registering with the server…',
      ApnsStatus.ready => switch (dropped) {
        0 => 'Active. Receiving notifications.',
        1 => 'Active, but the server dropped this device once',
        _ => 'Active, but the server dropped this device $dropped times',
      },
      ApnsStatus.pusherFailed => 'The server rejected the registration',
    };
