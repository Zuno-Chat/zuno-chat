import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';

DeliveryFailure? failureFor(
  NotificationDeliveryMode mode, {
  FcmStatus fcm = FcmStatus.idle,
  UnifiedPushStatus unifiedPush = UnifiedPushStatus.idle,
  bool distributorBatteryRestricted = false,
  String? distributor,
  NotificationDeliveryMode? autoSelected,
}) => notificationDeliveryFailure(
  mode: mode,
  fcm: fcm,
  unifiedPush: unifiedPush,
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

  test('every failure carries a message and exactly one action', () {
    for (final mode in NotificationDeliveryMode.values) {
      for (final fcm in FcmStatus.values) {
        for (final up in UnifiedPushStatus.values) {
          final failure = notificationDeliveryFailure(
            mode: mode,
            fcm: fcm,
            unifiedPush: up,
          );
          if (failure == null) continue;
          expect(failure.message, isNotEmpty, reason: '$mode/$fcm/$up');
          expect(
            deliveryFailureActionLabel(failure.action),
            isNotEmpty,
            reason: '$mode/$fcm/$up',
          );
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
