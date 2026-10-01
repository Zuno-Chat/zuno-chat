import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/features/settings/presentation/fcm_status_display.dart';

void main() {
  test('offers Register only before anything has been attempted', () {
    expect(fcmStatusAction(FcmStatus.idle), PushStatusAction.register);
  });

  test('offers Retry after a failure that trying again can clear', () {
    for (final status in [FcmStatus.tokenFailed, FcmStatus.pusherFailed]) {
      expect(
        fcmStatusAction(status),
        PushStatusAction.retry,
        reason: '$status',
      );
    }
  });

  test('offers the fix when Google Play services needs an update or is '
      'turned off', () {
    for (final status in [
      FcmStatus.playServicesUpdateRequired,
      FcmStatus.playServicesDisabled,
    ]) {
      expect(fcmStatusAction(status), PushStatusAction.fix, reason: '$status');
      expect(fcmStatusIsBusy(status), isFalse, reason: '$status');
    }
  });

  test('names the fix for what it does, and only where there is one', () {
    expect(
      fcmFixLabel(FcmStatus.playServicesUpdateRequired),
      'Update Google Play services',
    );
    expect(
      fcmFixLabel(FcmStatus.playServicesDisabled),
      'Turn on Google Play services',
    );
    for (final status in FcmStatus.values) {
      expect(
        fcmFixLabel(status) != null,
        fcmStatusAction(status) == PushStatusAction.fix,
        reason: '$status',
      );
    }
  });

  test('offers nothing while a step is in flight', () {
    for (final status in [
      FcmStatus.checkingPlayServices,
      FcmStatus.registering,
      FcmStatus.postingPusher,
    ]) {
      expect(fcmStatusAction(status), PushStatusAction.none, reason: '$status');
      expect(fcmStatusIsBusy(status), isTrue, reason: '$status');
    }
  });

  test('offers nothing when the device simply cannot run FCM', () {
    for (final status in [
      FcmStatus.playServicesUnavailable,
      FcmStatus.notConfigured,
    ]) {
      expect(fcmStatusAction(status), PushStatusAction.none, reason: '$status');
      expect(fcmStatusIsBusy(status), isFalse, reason: '$status');
    }
  });

  test('says why the device cannot use Google services', () {
    for (final (status, label) in [
      (
        FcmStatus.playServicesUnavailable,
        'This device does not have Google Play services',
      ),
      (
        FcmStatus.playServicesUpdateRequired,
        'Google Play services needs an update',
      ),
      (FcmStatus.playServicesDisabled, 'Google Play services is turned off'),
      (
        FcmStatus.notConfigured,
        'This version of Zuno does not include Google services',
      ),
    ]) {
      expect(fcmStatusLabel(status), label, reason: '$status');
    }
  });

  test('a working registration opens the details page', () {
    expect(fcmStatusAction(FcmStatus.ready), PushStatusAction.open);
    expect(fcmStatusIsBusy(FcmStatus.ready), isFalse);
  });

  test('every status has a label, and none of them shouts', () {
    for (final status in FcmStatus.values) {
      final label = fcmStatusLabel(status);
      expect(label, isNotEmpty, reason: '$status');
      expect(label, isNot(contains('!')), reason: '$status');
      expect(label, isNot(contains("'")), reason: '$status');
    }
  });
}
