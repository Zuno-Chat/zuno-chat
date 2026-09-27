import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';

DeliveryFailure? failureFor(
  NotificationDeliveryMode mode, {
  FcmStatus fcm = FcmStatus.idle,
  UnifiedPushStatus unifiedPush = UnifiedPushStatus.idle,
  ApnsStatus apns = ApnsStatus.idle,
  int apnsDropped = 0,
  bool distributorBatteryRestricted = false,
  String? distributor,
  NotificationDeliveryMode? autoSelected,
}) => notificationDeliveryFailure(
  mode: mode,
  fcm: fcm,
  unifiedPush: unifiedPush,
  apns: apns,
  apnsDropped: apnsDropped,
  distributorBatteryRestricted: distributorBatteryRestricted,
  distributor: distributor,
  autoSelected: autoSelected,
);

void main() {
  group('fcm', () {
    test('no Play Services offers the only transport that can work', () {
      final failure = failureFor(
        NotificationDeliveryMode.fcm,
        fcm: FcmStatus.playServicesUnavailable,
      );
      expect(failure?.action, DeliveryFailureAction.switchToUnifiedPush);
      expect(failure?.message, 'This device does not have Google services');
    });

    test('an update needed offers the one-tap fix, not a transport swap', () {
      final failure = failureFor(
        NotificationDeliveryMode.fcm,
        fcm: FcmStatus.playServicesUpdateRequired,
      );
      expect(failure?.action, DeliveryFailureAction.fixGoogleServices);
    });

    test('a token failure is worth retrying', () {
      expect(
        failureFor(
          NotificationDeliveryMode.fcm,
          fcm: FcmStatus.tokenFailed,
        )?.action,
        DeliveryFailureAction.retry,
      );
    });

    test('a rejected pusher is worth retrying', () {
      expect(
        failureFor(
          NotificationDeliveryMode.fcm,
          fcm: FcmStatus.pusherFailed,
        )?.action,
        DeliveryFailureAction.retry,
      );
    });

    test('ready and every in-flight state warn about nothing', () {
      for (final status in [
        FcmStatus.idle,
        FcmStatus.checkingPlayServices,
        FcmStatus.registering,
        FcmStatus.postingPusher,
        FcmStatus.ready,
      ]) {
        expect(
          failureFor(NotificationDeliveryMode.fcm, fcm: status),
          isNull,
          reason: '$status must not warn',
        );
      }
    });

    test('a UnifiedPush failure is invisible while FCM is the mode', () {
      expect(
        failureFor(
          NotificationDeliveryMode.fcm,
          fcm: FcmStatus.ready,
          unifiedPush: UnifiedPushStatus.registrationFailed,
        ),
        isNull,
      );
    });
  });

  group('unifiedPush', () {
    test('a refused registration is worth retrying', () {
      expect(
        failureFor(
          NotificationDeliveryMode.unifiedPush,
          unifiedPush: UnifiedPushStatus.registrationFailed,
        )?.action,
        DeliveryFailureAction.retry,
      );
    });

    test('a rejected pusher is worth retrying', () {
      expect(
        failureFor(
          NotificationDeliveryMode.unifiedPush,
          unifiedPush: UnifiedPushStatus.pusherFailed,
        )?.action,
        DeliveryFailureAction.retry,
      );
    });

    test('no distributor installed offers the transport that needs none', () {
      final failure = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPush: UnifiedPushStatus.noDistributorFound,
      );
      expect(failure?.action, DeliveryFailureAction.switchToBackgroundService);
      expect(
        failure?.message,
        'No distributor app on this device to deliver through',
      );
    });

    test('ready warns about nothing', () {
      expect(
        failureFor(
          NotificationDeliveryMode.unifiedPush,
          unifiedPush: UnifiedPushStatus.ready,
        ),
        isNull,
      );
    });
  });

  test('backgroundService has no registration to fail', () {
    for (final fcm in FcmStatus.values) {
      expect(
        failureFor(NotificationDeliveryMode.backgroundService, fcm: fcm),
        isNull,
      );
    }
  });

  test('a phone with no push infrastructure is never left with no button', () {
    final noPlayServices = failureFor(
      NotificationDeliveryMode.fcm,
      fcm: FcmStatus.playServicesUnavailable,
    );
    expect(noPlayServices?.action, DeliveryFailureAction.switchToUnifiedPush);

    final noDistributor = failureFor(
      NotificationDeliveryMode.unifiedPush,
      unifiedPush: UnifiedPushStatus.noDistributorFound,
    );
    expect(noDistributor, isNotNull, reason: 'silence here is the dead end');
    expect(
      noDistributor?.action,
      DeliveryFailureAction.switchToBackgroundService,
    );

    for (final up in UnifiedPushStatus.values) {
      expect(
        failureFor(NotificationDeliveryMode.backgroundService, unifiedPush: up),
        isNull,
      );
    }
  });

  group('apple push', () {
    test('never offers an Android fix, whatever the Android transports '
        'report', () {
      for (final fcm in FcmStatus.values) {
        for (final up in UnifiedPushStatus.values) {
          expect(
            failureFor(
              NotificationDeliveryMode.apns,
              fcm: fcm,
              unifiedPush: up,
              distributorBatteryRestricted: true,
              distributor: 'io.heckel.ntfy',
            ),
            isNull,
            reason: '$fcm/$up',
          );
        }
      }
    });

    test('a switch recorded for another method is not announced', () {
      expect(
        failureFor(
          NotificationDeliveryMode.apns,
          autoSelected: NotificationDeliveryMode.unifiedPush,
        ),
        isNull,
      );
    });

    test('a token Apple would not hand out offers a retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.apns,
        apns: ApnsStatus.tokenFailed,
      );
      expect(failure?.message, 'Could not set up notifications on this device');
      expect(failure?.action, DeliveryFailureAction.retry);
    });

    test('a registration the server refused offers a retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.apns,
        apns: ApnsStatus.pusherFailed,
      );
      expect(failure?.message, 'The server did not accept this device');
      expect(failure?.action, DeliveryFailureAction.retry);
    });

    test('a registration the server dropped is called out, with Retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.apns,
        apns: ApnsStatus.ready,
        apnsDropped: 1,
      );
      expect(
        failure?.message,
        'The server dropped this device, so notifications may not arrive',
      );
      expect(failure?.action, DeliveryFailureAction.retry);
    });

    test('a drop is reported only once registered again; a step in flight '
        'shows nothing and a failure wins', () {
      for (final apns in [ApnsStatus.registering, ApnsStatus.postingPusher]) {
        expect(
          failureFor(NotificationDeliveryMode.apns, apns: apns, apnsDropped: 1),
          isNull,
          reason: '$apns',
        );
      }
      expect(
        failureFor(
          NotificationDeliveryMode.apns,
          apns: ApnsStatus.pusherFailed,
          apnsDropped: 1,
        )?.message,
        'The server did not accept this device',
      );
    });

    test('a dropped Apple pusher never shows while another method is in '
        'use', () {
      for (final mode in [
        NotificationDeliveryMode.fcm,
        NotificationDeliveryMode.unifiedPush,
        NotificationDeliveryMode.backgroundService,
      ]) {
        expect(
          failureFor(mode, apns: ApnsStatus.ready, apnsDropped: 2),
          isNull,
          reason: '$mode',
        );
      }
    });

    test('in-progress and working states show nothing', () {
      for (final apns in [
        ApnsStatus.idle,
        ApnsStatus.registering,
        ApnsStatus.postingPusher,
        ApnsStatus.ready,
      ]) {
        expect(
          failureFor(NotificationDeliveryMode.apns, apns: apns),
          isNull,
          reason: '$apns',
        );
      }
    });

    test('a failed Apple push never shows while another method is in use', () {
      for (final mode in [
        NotificationDeliveryMode.fcm,
        NotificationDeliveryMode.unifiedPush,
        NotificationDeliveryMode.backgroundService,
      ]) {
        expect(
          failureFor(mode, apns: ApnsStatus.pusherFailed),
          isNull,
          reason: '$mode',
        );
      }
    });
  });

  test('every failure carries a message and exactly one action', () {
    for (final mode in NotificationDeliveryMode.values) {
      for (final fcm in FcmStatus.values) {
        for (final up in UnifiedPushStatus.values) {
          for (final apns in ApnsStatus.values) {
            final failure = notificationDeliveryFailure(
              mode: mode,
              fcm: fcm,
              unifiedPush: up,
              apns: apns,
            );
            if (failure == null) continue;
            expect(failure.message, isNotEmpty, reason: '$mode/$fcm/$up/$apns');
            expect(
              deliveryFailureActionLabel(failure.action),
              isNotEmpty,
              reason: '$mode/$fcm/$up/$apns',
            );
          }
        }
      }
    }
  });

  test('no failure message shouts or apologises', () {
    for (final mode in NotificationDeliveryMode.values) {
      for (final fcm in FcmStatus.values) {
        final failure = failureFor(mode, fcm: fcm);
        if (failure == null) continue;
        expect(failure.message, isNot(contains('!')));
        expect(failure.message.toLowerCase(), isNot(contains('sorry')));
        expect(failure.message.toLowerCase(), isNot(contains('error')));
      }
    }
  });

  group('distributor battery', () {
    test('a working UnifiedPush setup still warns when the distributor is '
        'battery-restricted, naming it', () {
      final failure = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPush: UnifiedPushStatus.ready,
        distributorBatteryRestricted: true,
        distributor: 'io.heckel.ntfy',
      );
      expect(failure?.action, DeliveryFailureAction.openDistributorSettings);
      expect(failure?.message, contains('ntfy'));
    });

    test('a registration failure outranks the battery warning', () {
      final failure = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPush: UnifiedPushStatus.registrationFailed,
        distributorBatteryRestricted: true,
        distributor: 'io.heckel.ntfy',
      );
      expect(failure?.action, DeliveryFailureAction.retry);
    });

    test('is irrelevant on FCM', () {
      expect(
        failureFor(
          NotificationDeliveryMode.fcm,
          fcm: FcmStatus.ready,
          distributorBatteryRestricted: true,
          distributor: 'io.heckel.ntfy',
        ),
        isNull,
      );
    });
  });

  group('auto-selected transport notice', () {
    test('explains the switch when nothing else is wrong', () {
      final notice = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPush: UnifiedPushStatus.ready,
        autoSelected: NotificationDeliveryMode.unifiedPush,
      );
      expect(notice?.notice, isTrue);
      expect(notice?.action, DeliveryFailureAction.openSettings);
      expect(notice?.message, contains('UnifiedPush'));
      expect(notice?.message, contains('Google'));
    });

    test('a real failure outranks the notice', () {
      final failure = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPush: UnifiedPushStatus.noDistributorFound,
        autoSelected: NotificationDeliveryMode.unifiedPush,
      );
      expect(failure?.notice, isFalse);
    });

    test('is not shown once the user has picked a different mode', () {
      expect(
        failureFor(
          NotificationDeliveryMode.fcm,
          fcm: FcmStatus.ready,
          autoSelected: NotificationDeliveryMode.unifiedPush,
        ),
        isNull,
      );
    });
  });
}
