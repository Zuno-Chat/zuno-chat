import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/features/settings/presentation/fcm_status_display.dart';

void main() {
  test('offers Register only before anything has been attempted', () {
    expect(fcmStatusAction(FcmStatus.idle), FcmStatusAction.register);
  });

  test('offers Retry after any failure the user can act on', () {
    for (final status in [
      FcmStatus.tokenFailed,
      FcmStatus.pusherFailed,
      FcmStatus.playServicesUpdateRequired,
    ]) {
      expect(fcmStatusAction(status), FcmStatusAction.retry, reason: '$status');
    }
  });

  test('offers nothing while a step is in flight', () {
    for (final status in [
      FcmStatus.checkingPlayServices,
      FcmStatus.registering,
      FcmStatus.postingPusher,
    ]) {
      expect(fcmStatusAction(status), FcmStatusAction.none, reason: '$status');
      expect(fcmStatusIsBusy(status), isTrue, reason: '$status');
    }
  });

  test('offers nothing when the device simply cannot run FCM', () {
    expect(
      fcmStatusAction(FcmStatus.playServicesUnavailable),
      FcmStatusAction.none,
    );
  });

  test('a working registration opens the details page', () {
    expect(fcmStatusAction(FcmStatus.ready), FcmStatusAction.open);
    expect(fcmStatusIsBusy(FcmStatus.ready), isFalse);
  });

  test('every status has a label, and none of them shouts', () {
    for (final status in FcmStatus.values) {
      final label = fcmStatusLabel(status);
      expect(label, isNotEmpty, reason: '$status');
      expect(label, isNot(contains('!')), reason: '$status');
    }
  });
}
