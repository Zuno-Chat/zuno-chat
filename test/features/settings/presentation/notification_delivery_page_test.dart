import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/fcm_availability_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';
import 'package:zuno/features/settings/presentation/push_target_status_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/fixed_delivery_mode.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/preferences_container.dart';

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  NotificationDeliveryMode mode, {
  PlatformCapabilities? capabilities,
  AsyncValue<FcmAvailability> fcm = const AsyncData(FcmAvailability.available),
  bool settle = true,
}) async {
  final container = await containerWithPreferences(
    {},
    overrides: [
      matrixClientProvider.overrideWithValue(buildTestClient()),
      fixedDeliveryMode(mode),
      fcmAvailabilityProvider.overrideWithValue(fcm),
      if (capabilities != null)
        platformCapabilitiesProvider.overrideWithValue(capabilities),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotificationDeliveryPage()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return container;
}

void main() {
  setUp(() {
    UnifiedPushPlatform.instance = FakeUnifiedPush();
  });

  testWidgets('shows the current method and explains the choices', (
    tester,
  ) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expect(find.text('Delivery method'), findsOneWidget);
    expect(
      find.text(NotificationDeliveryMode.backgroundService.label),
      findsOneWidget,
    );
    expect(
      find.text(
        'How messages and calls reach you while Zuno is closed. '
        'Background sync needs no setup. UnifiedPush needs a distributor '
        'app, such as ntfy, installed. Google services needs Google Play '
        'services.',
      ),
      findsOneWidget,
    );
    expect(find.text('Background data'), findsOneWidget);
  });

  testWidgets('FCM offers the battery exemption too, since it keeps a '
      'sleeping device from holding notifications back', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.text('Unrestricted battery usage'), findsOneWidget);
    expect(find.textContaining('can hold notifications back'), findsOneWidget);
  });

  group('autostart', () {
    late List<String> calls;

    void mockBackgroundSync({required bool hasAutostart}) {
      calls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('zuno/background_sync');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'hasAutostartSettings' => hasAutostart,
          'isIgnoringBatteryOptimizations' => false,
          'isBackgroundDataRestricted' => false,
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    testWidgets('gets a row on devices that stop closed apps from starting', (
      tester,
    ) async {
      mockBackgroundSync(hasAutostart: true);
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(find.text('Autostart'));
      await tester.pump();

      expect(calls, contains('openAutostartSettings'));
    });

    testWidgets('has no row elsewhere', (tester) async {
      mockBackgroundSync(hasAutostart: false);
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(find.text('Autostart'), findsNothing);
    });
  });

  testWidgets('Android offers its three methods and nothing else', (
    tester,
  ) async {
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    await tester.tap(find.text('Delivery method'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    for (final label in ['Google services', 'UnifiedPush', 'Background sync']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Apple push'), findsNothing);
  });

  group('battery and background data guidance', () {
    tearDown(() {
      unifiedPushDeliveryProvider.distributorBatteryRestricted.value = false;
      unifiedPushDeliveryProvider.savedDistributor = null;
    });

    testWidgets('no battery row where the platform has no battery exemption, '
        'even for a method that would show one', (tester) async {
      final noExemption = capabilitiesLike(
        androidCapabilities,
        batteryExemption: false,
      );
      for (final mode in androidCapabilities.deliveryModes) {
        await tester.pumpWidget(const SizedBox());
        await _pumpPage(tester, mode, capabilities: noExemption);

        expect(
          find.text('Unrestricted battery usage'),
          findsNothing,
          reason: mode.name,
        );
      }
    });

    testWidgets('no distributor battery row where the platform has no '
        'battery exemption', (tester) async {
      unifiedPushDeliveryProvider
        ..savedDistributor = 'io.heckel.ntfy'
        ..distributorBatteryRestricted.value = true;

      await _pumpPage(
        tester,
        NotificationDeliveryMode.unifiedPush,
        capabilities: capabilitiesLike(
          androidCapabilities,
          batteryExemption: false,
        ),
      );

      expect(find.text('ntfy battery', skipOffstage: false), findsNothing);
    });

    testWidgets('no background data row where the platform does not restrict '
        'it', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.backgroundService,
        capabilities: capabilitiesLike(
          androidCapabilities,
          backgroundDataRestriction: false,
        ),
      );

      expect(find.text('Background data'), findsNothing);
      expect(find.text('Unrestricted battery usage'), findsOneWidget);
    });
  });

  group('the UnifiedPush distributor lookup', () {
    late FakeUnifiedPush unifiedPush;

    setUp(() {
      unifiedPush = FakeUnifiedPush();
      UnifiedPushPlatform.instance = unifiedPush;
    });

    testWidgets('runs where UnifiedPush is on offer', (tester) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(unifiedPush.distributorReads, greaterThan(0));
    });

    testWidgets('never runs where it is not', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.fcm,
        capabilities: capabilitiesLike(
          androidCapabilities,
          deliveryModes: const [
            NotificationDeliveryMode.fcm,
            NotificationDeliveryMode.backgroundService,
          ],
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(unifiedPush.distributorReads, 0);
    });
  });

  group('with the push providers watched', () {
    late List<String> registrations;
    late List<MethodCall> syncCalls;
    late bool ignoringBattery;
    late bool dataRestricted;

    setUp(() {
      registrations = [];
      syncCalls = [];
      ignoringBattery = false;
      dataRestricted = false;
      final up = unifiedPushDeliveryProvider.notificationsAllowed;
      final fcm = fcmDeliveryProvider.notificationsAllowed;
      Future<bool> Function() recording(String name) => () async {
        registrations.add(name);
        return false;
      };
      unifiedPushDeliveryProvider.notificationsAllowed = recording(
        'unifiedPush',
      );
      fcmDeliveryProvider.notificationsAllowed = recording('fcm');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('zuno/background_sync');
      messenger.setMockMethodCallHandler(channel, (call) async {
        syncCalls.add(call);
        return switch (call.method) {
          'isIgnoringBatteryOptimizations' => ignoringBattery,
          'isBackgroundDataRestricted' => dataRestricted,
          'hasAutostartSettings' => false,
          _ => null,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        unifiedPushDeliveryProvider
          ..notificationsAllowed = up
          ..status.value = UnifiedPushStatus.idle
          ..savedDistributor = null
          ..distributorBatteryRestricted.value = false
          ..removed.value = false;
        fcmDeliveryProvider
          ..notificationsAllowed = fcm
          ..status.value = FcmStatus.idle;
      });
    });

    List<String> syncMethods() => [for (final c in syncCalls) c.method];

    Finder statusRow() => find.widgetWithText(ListTile, 'Status');

    Finder inStatusRow(Finder matching) =>
        find.descendant(of: statusRow(), matching: matching);

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Delivery method'));
      await tester.pumpAndSettle();
    }

    Finder inSheet(String label) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(label),
    );

    group('choosing a method', () {
      testWidgets('another one is saved and started', (tester) async {
        final container = await _pumpPage(
          tester,
          NotificationDeliveryMode.backgroundService,
        );

        await openSheet(tester);
        await tester.tap(inSheet('Google services'));
        await tester.pumpAndSettle();

        expect(
          container.read(notificationDeliveryModeProvider),
          NotificationDeliveryMode.fcm,
        );
        expect(
          container
              .read(sharedPreferencesProvider)
              .getString('settings.notification_delivery_mode'),
          'fcm',
        );
        expect(registrations, ['fcm']);
      });

      testWidgets('the current one is ticked and changes nothing', (
        tester,
      ) async {
        final container = await _pumpPage(tester, NotificationDeliveryMode.fcm);

        await openSheet(tester);
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Google services').last,
            matching: find.byIcon(Icons.check_outlined),
          ),
          findsOneWidget,
        );
        await tester.tap(inSheet('Google services'));
        await tester.pumpAndSettle();

        expect(registrations, isEmpty);
        expect(
          container
              .read(sharedPreferencesProvider)
              .getString('settings.notification_delivery_mode'),
          isNull,
        );
      });

      ListTile sheetRow(WidgetTester tester, String label) =>
          tester.widget<ListTile>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.widgetWithText(ListTile, label),
            ),
          );

      testWidgets('a device without Google Play services sees Google '
          'services listed, says why it cannot be picked, and tapping it '
          'changes nothing', (tester) async {
        final container = await _pumpPage(
          tester,
          NotificationDeliveryMode.backgroundService,
          fcm: const AsyncData(FcmAvailability.unavailable),
        );

        await openSheet(tester);
        expect(sheetRow(tester, 'Google services').enabled, isFalse);
        expect(
          inSheet('This device does not have Google Play services.'),
          findsOneWidget,
        );
        expect(sheetRow(tester, 'UnifiedPush').enabled, isTrue);
        expect(sheetRow(tester, 'Background sync').enabled, isTrue);

        await tester.tap(inSheet('Google services'));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          container.read(notificationDeliveryModeProvider),
          NotificationDeliveryMode.backgroundService,
        );
        expect(
          container
              .read(sharedPreferencesProvider)
              .getBool('settings.notification_delivery_mode_chosen'),
          isNull,
        );
        expect(registrations, isEmpty);
      });

      testWidgets('while this device is checked, Google services waits', (
        tester,
      ) async {
        await _pumpPage(
          tester,
          NotificationDeliveryMode.backgroundService,
          fcm: const AsyncLoading(),
        );

        await openSheet(tester);

        expect(sheetRow(tester, 'Google services').enabled, isFalse);
        expect(inSheet('Checking this device…'), findsOneWidget);
      });
    });

    group('battery and background data', () {
      testWidgets('an exempt device says so for each method', (tester) async {
        ignoringBattery = true;
        for (final (mode, subtitle) in [
          (
            NotificationDeliveryMode.fcm,
            'Android will not hold notifications back to save power',
          ),
          (
            NotificationDeliveryMode.backgroundService,
            'Android will not pause background sync to save power',
          ),
          (
            NotificationDeliveryMode.unifiedPush,
            'Android will not put Zuno to sleep, so notifications arrive '
                'while your device is locked',
          ),
        ]) {
          await tester.pumpWidget(const SizedBox());
          await _pumpPage(tester, mode);

          final row = find.widgetWithText(
            ListTile,
            'Unrestricted battery usage',
            skipOffstage: false,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.text(subtitle, skipOffstage: false),
            ),
            findsOneWidget,
            reason: mode.name,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.byIcon(
                Icons.check_circle_outline,
                skipOffstage: false,
              ),
            ),
            findsOneWidget,
            reason: mode.name,
          );
        }
      });

      testWidgets('tapping the battery row asks Android for the exemption', (
        tester,
      ) async {
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(find.text('Unrestricted battery usage'));
        await tester.pump();

        expect(syncMethods(), contains('requestIgnoreBatteryOptimizations'));
      });

      testWidgets('restricted background data says so and opens its '
          'setting', (tester) async {
        dataRestricted = true;
        await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

        expect(find.textContaining('Data Saver stops'), findsOneWidget);

        await tester.tap(find.text('Background data'));
        await tester.pump();

        expect(syncMethods(), contains('openBackgroundDataSettings'));
      });

      testWidgets('a battery-restricted distributor opens its own app '
          'settings', (tester) async {
        unifiedPushDeliveryProvider
          ..savedDistributor = 'io.heckel.ntfy'
          ..distributorBatteryRestricted.value = true;
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        await tester.scrollUntilVisible(
          find.text('ntfy battery'),
          200,
          scrollable: find.byType(Scrollable),
        );
        await tester.tap(find.text('ntfy battery'));
        await tester.pump();

        final open = syncCalls.singleWhere(
          (c) => c.method == 'openAppSettings',
        );
        expect(open.arguments, {'package': 'io.heckel.ntfy'});
      });
    });

    group('UnifiedPush status', () {
      testWidgets('an idle one on screen shows the paused icon', (
        tester,
      ) async {
        unifiedPushDeliveryProvider.status.value =
            UnifiedPushStatus.pusherFailed;
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        unifiedPushDeliveryProvider.status.value = UnifiedPushStatus.idle;
        await tester.pumpAndSettle();

        expect(
          inStatusRow(find.byIcon(Icons.pause_circle_outline)),
          findsOneWidget,
        );
      });

      testWidgets('a removed one offers Register, which registers again', (
        tester,
      ) async {
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        unifiedPushDeliveryProvider
          ..status.value = UnifiedPushStatus.idle
          ..removed.value = true;
        await tester.pumpAndSettle();
        registrations.clear();

        await tester.tap(
          inStatusRow(find.widgetWithText(TextButton, 'Register')),
        );
        await tester.pump();

        expect(registrations, ['unifiedPush']);
      });

      testWidgets('an idle one on opening looks for a distributor', (
        tester,
      ) async {
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        expect(
          unifiedPushDeliveryProvider.status.value,
          UnifiedPushStatus.noDistributorFound,
        );
      });

      for (final (status, icon) in [
        (UnifiedPushStatus.noDistributorFound, Icons.warning_amber_outlined),
        (
          UnifiedPushStatus.distributorSelected,
          Icons.arrow_circle_right_outlined,
        ),
        (UnifiedPushStatus.ready, Icons.check_circle_outline),
        (UnifiedPushStatus.registrationFailed, Icons.error_outline),
        (UnifiedPushStatus.pusherFailed, Icons.error_outline),
      ]) {
        testWidgets('${status.name} shows its icon', (tester) async {
          unifiedPushDeliveryProvider.status.value = status;
          await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

          expect(inStatusRow(find.byIcon(icon)), findsOneWidget);
        });
      }

      for (final status in [
        UnifiedPushStatus.findingDistributor,
        UnifiedPushStatus.registering,
        UnifiedPushStatus.postingPusher,
      ]) {
        testWidgets('${status.name} spins and holds off the refresh', (
          tester,
        ) async {
          unifiedPushDeliveryProvider.status.value = status;
          await _pumpPage(
            tester,
            NotificationDeliveryMode.unifiedPush,
            settle: false,
          );

          expect(
            inStatusRow(find.byType(CircularProgressIndicator)),
            findsOneWidget,
          );
          expect(
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.refresh),
                )
                .onPressed,
            isNull,
          );
          await tester.pumpWidget(const SizedBox());
        });
      }

      testWidgets('a refused registration offers Retry', (tester) async {
        unifiedPushDeliveryProvider.status.value =
            UnifiedPushStatus.pusherFailed;
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        await tester.tap(inStatusRow(find.text('Retry')));
        await tester.pump();

        expect(registrations, ['unifiedPush']);
      });

      testWidgets('a working registration says so and opens nothing', (
        tester,
      ) async {
        unifiedPushDeliveryProvider.status.value = UnifiedPushStatus.ready;
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        expect(
          find.descendant(
            of: statusRow(),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsNothing,
        );
        await tester.tap(statusRow());
        await tester.pumpAndSettle();

        expect(find.byType(PushTargetStatusPage), findsNothing);
      });

      testWidgets('refresh looks for a distributor and says when there is '
          'none', (tester) async {
        unifiedPushDeliveryProvider.status.value =
            UnifiedPushStatus.registrationFailed;
        await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        await tester.tap(find.byTooltip('Look for a distributor'));
        await tester.pumpAndSettle();

        expect(
          unifiedPushDeliveryProvider.status.value,
          UnifiedPushStatus.noDistributorFound,
        );
        expect(
          find.text('None installed. Install one, such as ntfy, then refresh.'),
          findsOneWidget,
        );
      });
    });

    group('Google services status', () {
      for (final (status, icon) in [
        (FcmStatus.idle, Icons.pause_circle_outline),
        (FcmStatus.playServicesUnavailable, Icons.warning_amber_outlined),
        (FcmStatus.playServicesDisabled, Icons.warning_amber_outlined),
        (FcmStatus.notConfigured, Icons.warning_amber_outlined),
        (FcmStatus.playServicesUpdateRequired, Icons.system_update_outlined),
        (FcmStatus.ready, Icons.check_circle_outline),
        (FcmStatus.tokenFailed, Icons.error_outline),
        (FcmStatus.pusherFailed, Icons.error_outline),
      ]) {
        testWidgets('${status.name} shows its icon', (tester) async {
          fcmDeliveryProvider.status.value = status;
          await _pumpPage(tester, NotificationDeliveryMode.fcm);

          expect(inStatusRow(find.byIcon(icon)), findsOneWidget);
        });
      }

      testWidgets('a step in flight spins', (tester) async {
        fcmDeliveryProvider.status.value = FcmStatus.registering;
        await _pumpPage(tester, NotificationDeliveryMode.fcm, settle: false);

        expect(
          inStatusRow(find.byType(CircularProgressIndicator)),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('an unregistered device offers Register', (tester) async {
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(inStatusRow(find.text('Register')));
        await tester.pump();

        expect(registrations, ['fcm']);
      });

      testWidgets('a failed token offers Retry', (tester) async {
        fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(inStatusRow(find.text('Retry')));
        await tester.pump();

        expect(registrations, ['fcm']);
      });

      testWidgets('an outdated Google Play services offers the update, named '
          'in full, and it starts the fix', (tester) async {
        var fixes = 0;
        final fixer = fcmDeliveryProvider.playServicesFixer;
        fcmDeliveryProvider.playServicesFixer = () async {
          fixes++;
          return FcmAvailability.updateRequired;
        };
        addTearDown(() => fcmDeliveryProvider.playServicesFixer = fixer);
        fcmDeliveryProvider.status.value = FcmStatus.playServicesUpdateRequired;
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(inStatusRow(find.byType(TextButton)), findsNothing);
        expect(find.text('Fix'), findsNothing);
        await tester.tap(find.text('Update Google Play services'));
        await tester.pump();

        expect(fixes, 1);
        expect(registrations, isEmpty);
        expect(
          fcmDeliveryProvider.status.value,
          FcmStatus.playServicesUpdateRequired,
        );
      });

      testWidgets('a status with nothing to fix offers no fix row', (
        tester,
      ) async {
        fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.text('Update Google Play services'), findsNothing);
        expect(find.text('Turn on Google Play services'), findsNothing);
      });

      testWidgets('a device that cannot run it offers nothing to tap', (
        tester,
      ) async {
        fcmDeliveryProvider.status.value = FcmStatus.notConfigured;
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(
          inStatusRow(
            find.text('This version of Zuno does not include Google services'),
          ),
          findsOneWidget,
        );
        expect(inStatusRow(find.byType(TextButton)), findsNothing);
      });

      testWidgets('a working registration says so and opens nothing', (
        tester,
      ) async {
        fcmDeliveryProvider.status.value = FcmStatus.ready;
        await _pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(
          find.descendant(
            of: statusRow(),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsNothing,
        );
        await tester.tap(statusRow());
        await tester.pumpAndSettle();

        expect(find.byType(PushTargetStatusPage), findsNothing);
      });
    });
  });
}
