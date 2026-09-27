import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/features/settings/presentation/apns_status_display.dart';
import 'package:zuno/features/settings/presentation/fcm_status_display.dart';

void main() {
  test('offers Register only before anything has been attempted', () {
    expect(apnsStatusAction(ApnsStatus.idle), PushStatusAction.register);
  });

  test('offers Retry after either failure', () {
    for (final status in [ApnsStatus.tokenFailed, ApnsStatus.pusherFailed]) {
      expect(
        apnsStatusAction(status),
        PushStatusAction.retry,
        reason: '$status',
      );
    }
  });

  test('offers nothing while a step is in flight', () {
    for (final status in [ApnsStatus.registering, ApnsStatus.postingPusher]) {
      expect(
        apnsStatusAction(status),
        PushStatusAction.none,
        reason: '$status',
      );
      expect(apnsStatusIsBusy(status), isTrue, reason: '$status');
    }
  });

  test('a working registration opens the details page', () {
    expect(apnsStatusAction(ApnsStatus.ready), PushStatusAction.open);
    expect(apnsStatusIsBusy(ApnsStatus.ready), isFalse);
  });

  test('a registration the server dropped says so, with the count', () {
    expect(
      apnsStatusLabel(ApnsStatus.ready, dropped: 1),
      'Active, but the server dropped this device once',
    );
    expect(
      apnsStatusLabel(ApnsStatus.ready, dropped: 3),
      'Active, but the server dropped this device 3 times',
    );
    expect(
      apnsStatusLabel(ApnsStatus.ready),
      'Active. Receiving notifications.',
    );
  });

  test('the drop count changes nothing while a step is failing or in '
      'flight', () {
    for (final status in ApnsStatus.values) {
      if (status == ApnsStatus.ready) continue;
      expect(
        apnsStatusLabel(status, dropped: 2),
        apnsStatusLabel(status),
        reason: '$status',
      );
    }
  });

  test('every status has a label, and none of them shouts', () {
    for (final status in ApnsStatus.values) {
      final label = apnsStatusLabel(status);
      expect(label, isNotEmpty, reason: '$status');
      expect(label, isNot(contains('!')), reason: '$status');
    }
  });
}
