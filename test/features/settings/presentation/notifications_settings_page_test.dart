import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_preview.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/push_diagnostics_report.dart';
import 'package:zuno/core/push/push_diagnostics_source.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';
import 'package:zuno/features/settings/presentation/notifications_settings_page.dart';
import 'package:zuno/features/settings/presentation/push_diagnostics_page.dart';
import 'package:zuno/features/settings/presentation/push_target_status_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/platform_capabilities.dart';

class _FixedDeliveryModeNotifier extends NotificationDeliveryModeNotifier {
  _FixedDeliveryModeNotifier(this._mode);
  final NotificationDeliveryMode _mode;

  @override
  NotificationDeliveryMode build() => _mode;
}

class _PusherRecordingClient extends Client {
  _PusherRecordingClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  final posted = <Pusher>[];

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async =>
      posted.add(pusher);

  @override
  Future<void> deletePusher(PusherId pusherId) async {}
}

void _stubNotificationPermission({required bool granted}) {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async =>
        call.method == 'checkPermissionStatus' ? (granted ? 1 : 0) : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  NotificationDeliveryMode mode, {
  PlatformCapabilities? capabilities,
  Client? client,
  List<Override> overrides = const [],
  String osVersion = '27.0',
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      matrixClientProvider.overrideWithValue(client ?? buildTestClient()),
      notificationDeliveryModeProvider.overrideWith(
        () => _FixedDeliveryModeNotifier(mode),
      ),
      if (capabilities != null)
        platformCapabilitiesProvider.overrideWithValue(capabilities),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: NotificationsSettingsPage(osVersion: osVersion)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _DiagnosticsSource implements PushDiagnosticsSource {
  @override
  Future<PushDiagnosticsInputs> load(PlatformCapabilities capabilities) async =>
      PushDiagnosticsInputs(
        capabilities: capabilities,
        now: DateTime(2026, 10, 2),
        appVersion: '1.2.0 (build 2)',
      );

  @override
  Future<PushTestOutcome> sendTest() async => PushTestOutcome.sent;
}

void main() {
  setUp(() {
    UnifiedPushPlatform.instance = FakeUnifiedPush();
  });

  testWidgets('every setting sits on a card', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expectEveryRowOnACard();
  });

  testWidgets('the Delivery row names the method in use', (tester) async {
    _stubNotificationPermission(granted: true);
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Delivery'),
    );
    expect(
      (row.subtitle! as Text).data,
      NotificationDeliveryMode.backgroundService.label,
    );
  });

  testWidgets('transport rows are off this page, whatever the method', (
    tester,
  ) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expect(find.text('Delivery method'), findsNothing);
    expect(find.text('Unrestricted battery usage'), findsNothing);
    expect(find.text('Background data'), findsNothing);
    expect(find.text('Status'), findsNothing);
  });

  testWidgets('everyday rows stay', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.text('Mentions only'), findsOneWidget);
    expect(find.text('Ringtone'), findsOneWidget);
  });

  testWidgets('tapping Delivery opens the delivery page', (tester) async {
    _stubNotificationPermission(granted: true);
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    await tester.tap(find.widgetWithText(ListTile, 'Delivery'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDeliveryPage), findsOneWidget);
    expect(find.text('Delivery method'), findsOneWidget);
  });

  testWidgets('with notifications off there are no Delivery or full-screen '
      'call rows', (tester) async {
    _stubNotificationPermission(granted: false);
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Delivery'), findsNothing);
    expect(find.text('Full-screen call alerts'), findsNothing);
  });

  testWidgets('with notifications on both rows are there', (tester) async {
    _stubNotificationPermission(granted: true);
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
    expect(find.text('Full-screen call alerts'), findsOneWidget);
  });

  group('where calls cannot take over the lock screen', () {
    testWidgets('there is no Full-screen call alerts row', (tester) async {
      _stubNotificationPermission(granted: true);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.fcm,
        capabilities: capabilitiesLike(
          androidCapabilities,
          fullScreenIntent: false,
        ),
      );

      expect(find.text('Full-screen call alerts'), findsNothing);
      expect(find.textContaining('takes over the screen'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
    });

    testWidgets('iOS has no row either', (tester) async {
      _stubNotificationPermission(granted: true);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
      );

      expect(find.text('Full-screen call alerts'), findsNothing);
    });
  });

  testWidgets('Android keeps the Full-screen call alerts row', (tester) async {
    _stubNotificationPermission(granted: true);
    await _pumpPage(
      tester,
      NotificationDeliveryMode.fcm,
      capabilities: androidCapabilities,
    );

    expect(find.text('Full-screen call alerts'), findsOneWidget);
  });

  testWidgets('with push diagnostics a Diagnostics row opens the diagnostics', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      NotificationDeliveryMode.apns,
      capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: true),
      overrides: [
        pushDiagnosticsSourceProvider.overrideWithValue(_DiagnosticsSource()),
      ],
    );

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.byType(PushDiagnosticsPage), findsOneWidget);
  });

  testWidgets('Android has no Diagnostics row', (tester) async {
    await _pumpPage(
      tester,
      NotificationDeliveryMode.fcm,
      capabilities: androidCapabilities,
    );

    expect(find.text('Diagnostics'), findsNothing);
  });

  group('on Android, Enable notifications', () {
    String subtitle(WidgetTester tester) =>
        (tester
                    .widget<SwitchListTile>(
                      find.widgetWithText(
                        SwitchListTile,
                        'Enable notifications',
                      ),
                    )
                    .subtitle!
                as Text)
            .data!;

    for (final mode in [
      NotificationDeliveryMode.fcm,
      NotificationDeliveryMode.unifiedPush,
    ]) {
      testWidgets('with ${mode.name} says only that calls can ring full '
          'screen, next to the Delivery row', (tester) async {
        _stubNotificationPermission(granted: true);
        await _pumpPage(tester, mode, capabilities: androidCapabilities);

        expect(subtitle(tester), 'Calls can ring full screen');
        expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
      });
    }

    testWidgets('with background sync also says where its status shows', (
      tester,
    ) async {
      _stubNotificationPermission(granted: true);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.backgroundService,
        capabilities: androidCapabilities,
      );

      expect(
        subtitle(tester),
        'Calls can ring full screen, and background sync shows its status in '
        'the notification shade',
      );
    });

    testWidgets('while off says nothing is delivered, whatever the method', (
      tester,
    ) async {
      _stubNotificationPermission(granted: false);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.backgroundService,
        capabilities: androidCapabilities,
      );

      expect(
        subtitle(tester),
        'Off. This device is not registered for notifications, so nothing is '
        'delivered to it.',
      );
    });
  });

  testWidgets('Android leaves a delivery problem to the banner and the '
      'Delivery page', (tester) async {
    fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;
    addTearDown(() => fcmDeliveryProvider.status.value = FcmStatus.idle);
    _stubNotificationPermission(granted: true);
    await _pumpPage(
      tester,
      NotificationDeliveryMode.fcm,
      capabilities: androidCapabilities,
    );

    expect(
      find.text('Could not set up notifications on this device'),
      findsNothing,
    );
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
  });

  group('where notifications have one way to arrive', () {
    late _PusherRecordingClient client;

    setUp(() {
      ambientCapabilities = iosCapabilities;
      client = _PusherRecordingClient();
      final tokenReader = apnsDeliveryProvider.tokenReader;
      final notificationsAllowed = apnsDeliveryProvider.notificationsAllowed;
      final environmentReader = apnsDeliveryProvider.environmentReader;
      apnsDeliveryProvider
        ..tokenReader = (() async => 'a1b2c3d4' * 8)
        ..notificationsAllowed = (() async => true)
        ..environmentReader = (() async => 'development');
      addTearDown(() async {
        await apnsDeliveryProvider.stop(client);
        apnsDeliveryProvider
          ..tokenReader = tokenReader
          ..notificationsAllowed = notificationsAllowed
          ..environmentReader = environmentReader
          ..resetEnvironmentForTesting();
      });
    });

    Future<ProviderContainer> pumpApplePush(
      WidgetTester tester, {
      ApnsStatus status = ApnsStatus.ready,
      int dropped = 0,
      bool granted = true,
      List<Override> overrides = const [],
    }) {
      apnsDeliveryProvider
        ..status.value = status
        ..dropped.value = dropped;
      _stubNotificationPermission(granted: granted);
      return _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
        client: client,
        overrides: overrides,
      );
    }

    Finder retry() => find.widgetWithText(TextButton, 'Retry');

    testWidgets('there is no Delivery row', (tester) async {
      await pumpApplePush(tester);

      expect(find.widgetWithText(ListTile, 'Delivery'), findsNothing);
      expect(find.byIcon(Icons.cloud_sync_outlined), findsNothing);
    });

    testWidgets('with diagnostics on, Push target opens the page that shows '
        'them', (tester) async {
      const channel = MethodChannel('zuno/push_diag');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      _stubNotificationPermission(granted: true);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: true),
        client: client,
      );

      final row = find.widgetWithText(ListTile, 'Push target');
      expect(
        find.descendant(
          of: row,
          matching: find.text('How notifications reach this device'),
        ),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(PushTargetStatusPage), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
    });

    testWidgets('with diagnostics off there is no Push target row', (
      tester,
    ) async {
      _stubNotificationPermission(granted: true);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: false),
        client: client,
      );

      expect(find.widgetWithText(ListTile, 'Push target'), findsNothing);
    });

    testWidgets('with notifications off there is no Push target row', (
      tester,
    ) async {
      _stubNotificationPermission(granted: false);
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: true),
        client: client,
      );

      expect(find.widgetWithText(ListTile, 'Push target'), findsNothing);
    });

    testWidgets('Enable notifications says what it does on this device', (
      tester,
    ) async {
      await pumpApplePush(tester);

      expect(
        find.text(
          'New messages show on this device, even while Zuno is closed',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('full screen'), findsNothing);
      expect(find.textContaining('background sync'), findsNothing);
    });

    for (final (name, status, dropped, message) in [
      (
        'a token that never came',
        ApnsStatus.tokenFailed,
        0,
        'Could not set up notifications on this device',
      ),
      (
        'a refused registration',
        ApnsStatus.pusherFailed,
        0,
        'Could not set up notifications on this device',
      ),
      (
        'a dropped registration',
        ApnsStatus.ready,
        2,
        'Notifications may not reach this device',
      ),
    ]) {
      testWidgets('$name shows on the first card, and Retry registers this '
          'device again', (tester) async {
        await pumpApplePush(tester, status: status, dropped: dropped);

        final row = find.widgetWithText(ListTile, message);
        expect(
          find.descendant(of: find.byType(CardGroup).first, matching: row),
          findsOneWidget,
        );
        final icon = tester.widget<Icon>(
          find.descendant(of: row, matching: find.byIcon(Icons.error_outline)),
        );
        expect(icon.color, Theme.of(tester.element(row)).colorScheme.error);

        await tester.tap(find.descendant(of: row, matching: retry()));
        await tester.pumpAndSettle();

        expect(client.posted, hasLength(1));
        expect(apnsDeliveryProvider.status.value, ApnsStatus.ready);
        expect(apnsDeliveryProvider.dropped.value, 0);
        expect(find.text(message), findsNothing);
        expect(retry(), findsNothing);
      });
    }

    for (final status in [
      ApnsStatus.ready,
      ApnsStatus.registering,
      ApnsStatus.postingPusher,
    ]) {
      testWidgets('${status.name} shows no problem', (tester) async {
        await pumpApplePush(tester, status: status);

        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(retry(), findsNothing);
      });
    }

    testWidgets('with notifications off no problem shows, even one still '
        'reported', (tester) async {
      const failure = DeliveryFailure(
        message: 'Could not set up notifications on this device',
        action: DeliveryFailureAction.retry,
      );
      await pumpApplePush(
        tester,
        status: ApnsStatus.tokenFailed,
        granted: false,
        overrides: [deliveryFailureProvider.overrideWithValue(failure)],
      );

      expect(find.text(failure.message), findsNothing);
      expect(retry(), findsNothing);
    });

    testWidgets('a reported problem shows once notifications are on', (
      tester,
    ) async {
      const failure = DeliveryFailure(
        message: 'Could not set up notifications on this device',
        action: DeliveryFailureAction.retry,
      );
      await pumpApplePush(
        tester,
        overrides: [deliveryFailureProvider.overrideWithValue(failure)],
      );

      expect(find.text(failure.message), findsOneWidget);
      expect(retry(), findsOneWidget);
    });

    testWidgets('a problem dismissed on the home banner still shows here', (
      tester,
    ) async {
      final container = await pumpApplePush(
        tester,
        status: ApnsStatus.pusherFailed,
      );

      container
          .read(dismissedDeliveryFailureProvider.notifier)
          .dismiss(container.read(deliveryFailureProvider)!);
      await tester.pump();

      expect(
        find.text('Could not set up notifications on this device'),
        findsOneWidget,
      );
      expect(retry(), findsOneWidget);
    });

    testWidgets('retrying here brings back the banner it was dismissed '
        'from', (tester) async {
      final container = await pumpApplePush(
        tester,
        status: ApnsStatus.pusherFailed,
      );
      container
          .read(dismissedDeliveryFailureProvider.notifier)
          .dismiss(container.read(deliveryFailureProvider)!);
      apnsDeliveryProvider.tokenReader = () async =>
          throw PlatformException(code: 'unavailable');

      await tester.tap(retry());
      await tester.pump();

      expect(apnsDeliveryProvider.status.value, ApnsStatus.tokenFailed);
      expect(container.read(dismissedDeliveryFailureProvider), isNull);
      await apnsDeliveryProvider.stop(client);
    });
  });

  group('where the app cannot vibrate', () {
    testWidgets('there are no vibration switches', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.fcm,
        capabilities: capabilitiesLike(
          androidCapabilities,
          vibrationPatterns: false,
        ),
      );

      expect(find.text('Vibrate for calls'), findsNothing);
      expect(find.text('Vibrate for messages'), findsNothing);
      expect(find.text('Sounds & vibration'), findsNothing);
      expect(find.text('Sounds'), findsOneWidget);
      expect(find.text('Ringtone'), findsOneWidget);
      expect(find.text('Message tone'), findsOneWidget);
    });

    testWidgets('iOS has none either', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
      );

      expect(find.text('Vibrate for calls'), findsNothing);
      expect(find.text('Vibrate for messages'), findsNothing);
      expect(find.text('Sounds'), findsOneWidget);
    });
  });

  testWidgets('Android keeps both vibration switches', (tester) async {
    await _pumpPage(
      tester,
      NotificationDeliveryMode.fcm,
      capabilities: androidCapabilities,
    );

    expect(find.text('Sounds & vibration'), findsOneWidget);
    expect(find.text('Vibrate for calls'), findsOneWidget);
    expect(find.text('Vibrate for messages'), findsOneWidget);
  });

  testWidgets('mentions only says other messages still show, silently', (
    tester,
  ) async {
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.text('Other messages show silently'), findsOneWidget);
  });

  group('the Enable notifications switch', () {
    late List<String> callsMade;
    late List<String> permissionCalls;
    var status = 0;

    setUp(() {
      callsMade = [];
      permissionCalls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const calls = MethodChannel('zuno/calls');
      const permissions = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      messenger.setMockMethodCallHandler(calls, (call) async {
        callsMade.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(permissions, (call) async {
        permissionCalls.add(call.method);
        return switch (call.method) {
          'checkPermissionStatus' => status,
          _ => null,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(calls, null);
        messenger.setMockMethodCallHandler(permissions, null);
      });
    });

    testWidgets('turned off, opens the notification settings, not app info', (
      tester,
    ) async {
      status = 1;
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable notifications'),
      );
      await tester.pump();

      expect(callsMade, contains('openNotificationSettings'));
      expect(permissionCalls, isNot(contains('openAppSettings')));
    });

    testWidgets('turned on after a permanent refusal, opens them too', (
      tester,
    ) async {
      status = 4;
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable notifications'),
      );
      await tester.pump();

      expect(callsMade, contains('openNotificationSettings'));
      expect(permissionCalls, isNot(contains('requestPermissions')));
    });
  });

  group('a silenced chat channel', () {
    late List<MethodCall> callsMade;

    setUp(() {
      callsMade = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const calls = MethodChannel('zuno/calls');
      const permissions = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      messenger.setMockMethodCallHandler(calls, (call) async {
        callsMade.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(
        permissions,
        (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(calls, null);
        messenger.setMockMethodCallHandler(permissions, null);
      });
    });

    testWidgets('gets a row that opens its system settings', (tester) async {
      installFakeLocalNotifications().deviceChannels = [
        deviceChannel('group_messages', name: 'Room messages', importance: 2),
        deviceChannel('direct_messages', name: 'Chat messages', importance: 4),
      ];
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(find.text('Room messages are silenced'), findsOneWidget);
      expect(find.text('Chat messages are silenced'), findsNothing);

      await tester.tap(find.text('Room messages are silenced'));
      await tester.pump();

      final open = callsMade.singleWhere(
        (c) => c.method == 'openChannelSettings',
      );
      expect((open.arguments as Map)['channelId'], 'group_messages');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('shows nothing while every chat channel can alert', (
      tester,
    ) async {
      installFakeLocalNotifications().deviceChannels = [
        deviceChannel('group_messages', name: 'Room messages', importance: 4),
      ];
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(find.textContaining('are silenced'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('asking for the permission', () {
    late int status;
    late int requestAnswer;
    late List<String> permissionCalls;
    late List<String> syncCalls;
    Completer<void>? statusGate;

    setUp(() {
      status = 0;
      requestAnswer = 1;
      permissionCalls = [];
      syncCalls = [];
      statusGate = null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const permissions = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      const backgroundSync = MethodChannel('zuno/background_sync');
      messenger.setMockMethodCallHandler(permissions, (call) async {
        permissionCalls.add(call.method);
        switch (call.method) {
          case 'checkPermissionStatus':
            await statusGate?.future;
            return status;
          case 'requestPermissions':
            return {17: requestAnswer};
        }
        return null;
      });
      messenger.setMockMethodCallHandler(backgroundSync, (call) async {
        syncCalls.add(call.method);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(permissions, null);
        messenger.setMockMethodCallHandler(backgroundSync, null);
      });
    });

    Finder toggle() =>
        find.widgetWithText(SwitchListTile, 'Enable notifications');

    testWidgets('turning it on asks, and a yes brings the delivery rows and '
        'restarts background sync', (tester) async {
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);
      expect(find.widgetWithText(ListTile, 'Delivery'), findsNothing);

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(permissionCalls, contains('requestPermissions'));
      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
      expect(syncCalls, ['startBackgroundSyncService']);
    });

    testWidgets('a no keeps it off and says nothing is delivered', (
      tester,
    ) async {
      requestAnswer = 0;
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      expect(find.textContaining('nothing is delivered'), findsOneWidget);
      expect(syncCalls, isEmpty);
    });

    testWidgets('with push delivery a yes leaves background sync alone', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      expect(syncCalls, isEmpty);
    });

    testWidgets('coming back from system settings picks up the change', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);
      status = 1;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      expect(syncCalls, ['startBackgroundSyncService']);
    });

    testWidgets('closing the page mid-check is harmless', (tester) async {
      statusGate = Completer();
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

      await tester.pumpWidget(const SizedBox());
      statusGate!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('full-screen call alerts', () {
    late List<String> callsMade;

    setUp(() {
      callsMade = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const calls = MethodChannel('zuno/calls');
      messenger.setMockMethodCallHandler(calls, (call) async {
        callsMade.add(call.method);
        return call.method == 'canUseFullScreenIntent' ? false : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(calls, null));
    });

    testWidgets('when turned off say so and open the setting', (tester) async {
      _stubNotificationPermission(granted: true);
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      final row = find.widgetWithText(ListTile, 'Full-screen call alerts');
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('only as a regular notification'),
        ),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pump();

      expect(callsMade, contains('openFullScreenIntentSettings'));
    });
  });

  group('preferences', () {
    Finder switchTile(String title) =>
        find.widgetWithText(SwitchListTile, title);

    testWidgets('Mentions only is kept', (tester) async {
      final container = await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(find.text('Mentions only'));
      await tester.pump();

      expect(container.read(notifyMeProvider), NotifyMe.mentionsOnly);
      expect(
        tester
            .widget<RadioGroup<NotifyMe>>(find.byType(RadioGroup<NotifyMe>))
            .groupValue,
        NotifyMe.mentionsOnly,
      );
    });

    for (final (title, provider) in [
      ('Ringtone', ringtoneEnabledProvider),
      ('Vibrate for calls', callVibrationEnabledProvider),
      ('Message tone', messageToneEnabledProvider),
      ('Vibrate for messages', messageVibrationEnabledProvider),
    ]) {
      testWidgets('$title flips its setting', (tester) async {
        final container = await _pumpPage(tester, NotificationDeliveryMode.fcm);
        final before = container.read(provider);

        await tester.tap(switchTile(title));
        await tester.pump();

        expect(container.read(provider), !before);
        expect(tester.widget<SwitchListTile>(switchTile(title)).value, !before);
      });
    }
  });

  group('Message tone with an Apple pusher registered', () {
    late _PusherRecordingClient client;

    setUp(() {
      ambientCapabilities = iosCapabilities;
      client = _PusherRecordingClient();
      final tokenReader = apnsDeliveryProvider.tokenReader;
      final notificationsAllowed = apnsDeliveryProvider.notificationsAllowed;
      final environmentReader = apnsDeliveryProvider.environmentReader;
      apnsDeliveryProvider
        ..tokenReader = (() async => 'a1b2c3d4' * 8)
        ..notificationsAllowed = (() async => true)
        ..environmentReader = (() async => 'development');
      addTearDown(() async {
        await apnsDeliveryProvider.stop(client);
        apnsDeliveryProvider
          ..tokenReader = tokenReader
          ..notificationsAllowed = notificationsAllowed
          ..environmentReader = environmentReader
          ..resetEnvironmentForTesting();
      });
    });

    Object? soundOf(Pusher pusher) =>
        ((pusher.data.toJson()['default_payload'] as Map)['aps']
            as Map)['sound'];

    Finder messageTone() => find.widgetWithText(SwitchListTile, 'Message tone');

    testWidgets('on iOS, turning it off re-posts the pusher without a sound', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
        client: client,
      );
      await apnsDeliveryProvider.start(client);

      await tester.tap(messageTone());
      await tester.pumpAndSettle();

      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
      expect(apnsDeliveryProvider.status.value, ApnsStatus.ready);
    });

    testWidgets('on iOS, turning it back on re-posts it with the sound', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
        client: client,
      );
      await apnsDeliveryProvider.start(client);

      await tester.tap(messageTone());
      await tester.pumpAndSettle();
      await tester.tap(messageTone());
      await tester.pumpAndSettle();

      expect(client.posted.map(soundOf), [
        'message_tone.caf',
        null,
        'message_tone.caf',
      ]);
    });

    testWidgets('on Android capabilities the switch leaves Apple push alone', (
      tester,
    ) async {
      final container = await _pumpPage(
        tester,
        NotificationDeliveryMode.fcm,
        capabilities: androidCapabilities,
        client: client,
      );
      await apnsDeliveryProvider.start(client);

      await tester.tap(messageTone());
      await tester.pumpAndSettle();

      expect(container.read(messageToneEnabledProvider), isFalse);
      expect(client.posted.map(soundOf), ['message_tone.caf']);
    });
  });

  group('notification content', () {
    final withExtension = capabilitiesLike(
      iosCapabilities,
      nseNotifications: true,
    );

    testWidgets('offers three levels with Name and message chosen', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: withExtension,
      );

      expect(find.text('Notification content'), findsOneWidget);
      expect(find.text('Name and message'), findsOneWidget);
      expect(find.text('Name only'), findsOneWidget);
      expect(find.text('Nothing'), findsOneWidget);
      final chosen = tester.widget<RadioGroup<NotificationPreview>>(
        find.byType(RadioGroup<NotificationPreview>),
      );
      expect(chosen.groupValue, NotificationPreview.full);
      expect(find.textContaining('message text stays in Zuno'), findsOneWidget);
    });

    testWidgets('choosing Nothing stores it', (tester) async {
      final container = await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: withExtension,
      );

      await tester.tap(find.text('Nothing'));
      await tester.pumpAndSettle();

      expect(
        container.read(notificationPreviewProvider),
        NotificationPreview.nothing,
      );
    });

    testWidgets('Android and an iOS build without the extension show none of '
        'it', (tester) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);
      expect(find.text('Notification content'), findsNothing);

      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: capabilitiesLike(
          iosCapabilities,
          nseNotifications: false,
        ),
      );
      expect(find.text('Notification content'), findsNothing);
    });

    testWidgets('an iOS version that keeps deleted notifications suggests '
        'Name only once', (tester) async {
      final container = await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: withExtension,
        osVersion: 'Version 26.4.1 (Build 23E246)',
      );

      await tester.tap(find.text('Use Name only'));
      await tester.pumpAndSettle();

      expect(
        container.read(notificationPreviewProvider),
        NotificationPreview.nameOnly,
      );
      expect(find.text('Use Name only'), findsNothing);
    });

    testWidgets('keeping the level also retires the suggestion', (
      tester,
    ) async {
      final container = await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: withExtension,
        osVersion: '18.7.7',
      );

      await tester.tap(find.text('Keep as is'));
      await tester.pumpAndSettle();

      expect(find.text('Keep as is'), findsNothing);
      expect(
        container.read(notificationPreviewProvider),
        NotificationPreview.full,
      );
    });

    testWidgets('a fixed iOS version gets no suggestion', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: withExtension,
        osVersion: '26.4.2',
      );

      expect(find.text('Use Name only'), findsNothing);
    });
  });
}
