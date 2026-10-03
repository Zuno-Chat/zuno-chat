import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';

DeliveryFailure? failureFor(
  NotificationDeliveryMode mode, {
  FcmStatus fcm = FcmStatus.idle,
  UnifiedPushStatus unifiedPush = UnifiedPushStatus.idle,
  ApnsStatus apns = ApnsStatus.idle,
  int apnsDropped = 0,
  bool distributorBatteryRestricted = false,
  String? distributor,
  bool? distributorInstalled,
  NotificationDeliveryMode? autoSelected,
  bool fcmRemoved = false,
  bool unifiedPushRemoved = false,
}) => notificationDeliveryFailure(
  mode: mode,
  fcm: fcm,
  unifiedPush: unifiedPush,
  apns: apns,
  apnsDropped: apnsDropped,
  distributorBatteryRestricted: distributorBatteryRestricted,
  distributor: distributor,
  distributorInstalled: distributorInstalled,
  autoSelected: autoSelected,
  fcmRemoved: fcmRemoved,
  unifiedPushRemoved: unifiedPushRemoved,
);

const _notRegistered = 'This device is not registered for notifications';

void main() {
  group('fcm', () {
    test('no Play Services offers the only transport that can work', () {
      final failure = failureFor(
        NotificationDeliveryMode.fcm,
        fcm: FcmStatus.playServicesUnavailable,
      );
      expect(failure?.action, DeliveryFailureAction.switchToUnifiedPush);
      expect(
        failure?.message,
        'This device does not have Google Play services',
      );
    });

    test('an update needed offers the one-tap update, not a transport '
        'swap', () {
      final failure = failureFor(
        NotificationDeliveryMode.fcm,
        fcm: FcmStatus.playServicesUpdateRequired,
      );
      expect(failure?.action, DeliveryFailureAction.updatePlayServices);
      expect(failure?.message, 'Google Play services needs an update');
      expect(
        deliveryFailureActionLabel(failure!.action),
        'Update Google Play services',
      );
    });

    group('where Google services cannot work', () {
      for (final status in [
        FcmStatus.playServicesUnavailable,
        FcmStatus.notConfigured,
      ]) {
        test('${status.name} with no distributor installed offers background '
            'sync directly', () {
          final failure = failureFor(
            NotificationDeliveryMode.fcm,
            fcm: status,
            distributorInstalled: false,
          );
          expect(
            failure?.action,
            DeliveryFailureAction.switchToBackgroundService,
          );
          expect(
            deliveryFailureActionLabel(failure!.action),
            'Use background sync',
          );
        });

        test('${status.name} with a distributor installed offers '
            'UnifiedPush', () {
          expect(
            failureFor(
              NotificationDeliveryMode.fcm,
              fcm: status,
              distributorInstalled: true,
            )?.action,
            DeliveryFailureAction.switchToUnifiedPush,
          );
        });

        test('${status.name} offers UnifiedPush until the distributors are '
            'known', () {
          expect(
            failureFor(NotificationDeliveryMode.fcm, fcm: status)?.action,
            DeliveryFailureAction.switchToUnifiedPush,
          );
        });
      }

      test('a device Zuno can fix is offered the fix, distributor or not', () {
        for (final (status, action) in [
          (
            FcmStatus.playServicesUpdateRequired,
            DeliveryFailureAction.updatePlayServices,
          ),
          (
            FcmStatus.playServicesDisabled,
            DeliveryFailureAction.turnOnPlayServices,
          ),
        ]) {
          for (final installed in [true, false, null]) {
            expect(
              failureFor(
                NotificationDeliveryMode.fcm,
                fcm: status,
                distributorInstalled: installed,
              )?.action,
              action,
              reason: '$status/$installed',
            );
          }
        }
      });

      test('a missing distributor changes nothing for the other methods', () {
        expect(
          failureFor(
            NotificationDeliveryMode.unifiedPush,
            unifiedPush: UnifiedPushStatus.ready,
            distributorInstalled: false,
          ),
          isNull,
        );
        expect(
          failureFor(
            NotificationDeliveryMode.fcm,
            fcm: FcmStatus.tokenFailed,
            distributorInstalled: false,
          )?.action,
          DeliveryFailureAction.retry,
        );
      });
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

    test('a refused registration reads like a missing token, with a '
        'retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.fcm,
        fcm: FcmStatus.pusherFailed,
      );
      expect(failure?.message, 'Could not set up notifications on this device');
      expect(failure?.action, DeliveryFailureAction.retry);
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

    test('a refused registration reads like a missing token, with a '
        'retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPush: UnifiedPushStatus.pusherFailed,
      );
      expect(failure?.message, 'Could not set up notifications on this device');
      expect(failure?.action, DeliveryFailureAction.retry);
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

  group('a push target the user removed', () {
    test('with Google services says this device is not registered, with '
        'Retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.fcm,
        fcmRemoved: true,
      );
      expect(failure?.message, _notRegistered);
      expect(failure?.action, DeliveryFailureAction.retry);
      expect(failure?.notice, isFalse);
    });

    test('with UnifiedPush says so too, whether or not a distributor is '
        'picked', () {
      for (final status in [
        UnifiedPushStatus.idle,
        UnifiedPushStatus.distributorSelected,
      ]) {
        final failure = failureFor(
          NotificationDeliveryMode.unifiedPush,
          unifiedPush: status,
          unifiedPushRemoved: true,
        );
        expect(failure?.message, _notRegistered, reason: '$status');
        expect(failure?.action, DeliveryFailureAction.retry, reason: '$status');
      }
    });

    test('says nothing while a registration is in flight or working', () {
      for (final fcm in [
        FcmStatus.checkingPlayServices,
        FcmStatus.registering,
        FcmStatus.postingPusher,
        FcmStatus.ready,
      ]) {
        expect(
          failureFor(NotificationDeliveryMode.fcm, fcm: fcm, fcmRemoved: true),
          isNull,
          reason: '$fcm',
        );
      }
      for (final unifiedPush in [
        UnifiedPushStatus.findingDistributor,
        UnifiedPushStatus.registering,
        UnifiedPushStatus.postingPusher,
        UnifiedPushStatus.ready,
      ]) {
        expect(
          failureFor(
            NotificationDeliveryMode.unifiedPush,
            unifiedPush: unifiedPush,
            unifiedPushRemoved: true,
          ),
          isNull,
          reason: '$unifiedPush',
        );
      }
    });

    test('a failure since then keeps its own message and action', () {
      expect(
        failureFor(
          NotificationDeliveryMode.fcm,
          fcm: FcmStatus.playServicesDisabled,
          fcmRemoved: true,
        )?.action,
        DeliveryFailureAction.turnOnPlayServices,
      );
      expect(
        failureFor(
          NotificationDeliveryMode.unifiedPush,
          unifiedPush: UnifiedPushStatus.noDistributorFound,
          unifiedPushRemoved: true,
        )?.action,
        DeliveryFailureAction.switchToBackgroundService,
      );
    });

    test('never shows while another method is in use', () {
      expect(
        failureFor(NotificationDeliveryMode.unifiedPush, fcmRemoved: true),
        isNull,
      );
      expect(
        failureFor(NotificationDeliveryMode.fcm, unifiedPushRemoved: true),
        isNull,
      );
      for (final mode in [
        NotificationDeliveryMode.backgroundService,
        NotificationDeliveryMode.apns,
      ]) {
        expect(
          failureFor(mode, fcmRemoved: true, unifiedPushRemoved: true),
          isNull,
          reason: '$mode',
        );
      }
    });

    test('outranks the switched-method notice', () {
      final failure = failureFor(
        NotificationDeliveryMode.unifiedPush,
        unifiedPushRemoved: true,
        autoSelected: NotificationDeliveryMode.unifiedPush,
      );
      expect(failure?.message, _notRegistered);
      expect(failure?.notice, isFalse);
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

  test('a turned-off Google Play services offers to turn it on', () {
    final failure = failureFor(
      NotificationDeliveryMode.fcm,
      fcm: FcmStatus.playServicesDisabled,
    );
    expect(failure?.message, 'Google Play services is turned off');
    expect(failure?.action, DeliveryFailureAction.turnOnPlayServices);
    expect(
      deliveryFailureActionLabel(failure!.action),
      'Turn on Google Play services',
    );
  });

  test('an action that acts on Google Play services calls it by that '
      'name', () {
    for (final action in DeliveryFailureAction.values) {
      final label = deliveryFailureActionLabel(action);
      if (!label.contains('Google')) continue;
      expect(label, contains('Google Play services'), reason: '$action');
    }
  });

  test('a build without Google services offers another method', () {
    final failure = failureFor(
      NotificationDeliveryMode.fcm,
      fcm: FcmStatus.notConfigured,
    );
    expect(
      failure?.message,
      'This version of Zuno does not include Google services',
    );
    expect(failure?.action, DeliveryFailureAction.switchToUnifiedPush);
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

    test('a refused registration reads like a missing token, with a '
        'retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.apns,
        apns: ApnsStatus.pusherFailed,
      );
      expect(failure?.message, 'Could not set up notifications on this device');
      expect(failure?.action, DeliveryFailureAction.retry);
    });

    test('a dropped registration is called out, with Retry', () {
      final failure = failureFor(
        NotificationDeliveryMode.apns,
        apns: ApnsStatus.ready,
        apnsDropped: 1,
      );
      expect(failure?.message, 'Notifications may not reach this device');
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
        'Could not set up notifications on this device',
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
            for (final installed in [true, false, null]) {
              for (final removed in [false, true]) {
                final failure = notificationDeliveryFailure(
                  mode: mode,
                  fcm: fcm,
                  unifiedPush: up,
                  apns: apns,
                  distributorInstalled: installed,
                  fcmRemoved: removed,
                  unifiedPushRemoved: removed,
                );
                if (failure == null) continue;
                final reason = '$mode/$fcm/$up/$apns/$installed/$removed';
                expect(failure.message, isNotEmpty, reason: reason);
                expect(
                  deliveryFailureActionLabel(failure.action),
                  isNotEmpty,
                  reason: reason,
                );
              }
            }
          }
        }
      }
    }
  });

  test('no failure message names the server, shouts, apologises or uses a '
      'contraction', () {
    final messages = {
      for (final mode in NotificationDeliveryMode.values)
        for (final fcm in FcmStatus.values)
          for (final unifiedPush in UnifiedPushStatus.values)
            for (final apns in ApnsStatus.values)
              for (final dropped in [0, 1])
                for (final restricted in [false, true])
                  for (final distributor in [null, 'io.heckel.ntfy'])
                    for (final autoSelected in [null, mode])
                      for (final removed in [false, true])
                        ?failureFor(
                          mode,
                          fcm: fcm,
                          unifiedPush: unifiedPush,
                          apns: apns,
                          apnsDropped: dropped,
                          distributorBatteryRestricted: restricted,
                          distributor: distributor,
                          autoSelected: autoSelected,
                          fcmRemoved: removed,
                          unifiedPushRemoved: removed,
                        )?.message,
    };
    expect(messages, contains(_notRegistered));
    for (final message in messages) {
      expect(message.toLowerCase(), isNot(contains('server')), reason: message);
      expect(message, isNot(contains('!')), reason: message);
      expect(message, isNot(contains(RegExp("['’]"))), reason: message);
      expect(message.toLowerCase(), isNot(contains('sorry')), reason: message);
      expect(message.toLowerCase(), isNot(contains('error')), reason: message);
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
      expect(
        notice?.message,
        'Google services cannot be used, so notifications use UnifiedPush',
      );
    });

    test('names background sync when that is what Zuno switched to, in '
        'lower case as everywhere else mid-sentence', () {
      expect(
        failureFor(
          NotificationDeliveryMode.backgroundService,
          autoSelected: NotificationDeliveryMode.backgroundService,
        )?.message,
        'Google services cannot be used, so notifications use background '
        'sync',
      );
    });

    test('names each method the way the rest of Zuno does mid-sentence', () {
      for (final (mode, named) in [
        (NotificationDeliveryMode.backgroundService, 'background sync'),
        (NotificationDeliveryMode.unifiedPush, 'UnifiedPush'),
        (NotificationDeliveryMode.fcm, 'Google services'),
        (NotificationDeliveryMode.apns, 'Apple push'),
      ]) {
        expect(
          failureFor(
            mode,
            fcm: FcmStatus.ready,
            unifiedPush: UnifiedPushStatus.ready,
            apns: ApnsStatus.ready,
            autoSelected: mode,
          )?.message,
          endsWith('so notifications use $named'),
          reason: '$mode',
        );
      }
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

  test('only a refused call registration is shown, with Retry', () {
    for (final state in VoipRegistrationState.values) {
      expect(
        callsDeliveryFailure(state),
        state == VoipRegistrationState.failed ? callsMayNotRing : isNull,
        reason: state.name,
      );
    }
    expect(callsMayNotRing.message, 'Calls may not ring while Zuno is closed');
    expect(deliveryFailureActionLabel(callsMayNotRing.action), 'Retry');
  });
}
