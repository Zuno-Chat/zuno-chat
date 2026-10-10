import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
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
import 'package:zuno/core/push/recent_pushes.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';
import 'package:zuno/features/settings/presentation/notifications_settings_page.dart';
import 'package:zuno/features/settings/presentation/push_diagnostics_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_permissions.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/fixed_delivery_mode.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/pusher_recording_client.dart';

void _useApplePush(PusherRecordingClient client) {
  ambientCapabilities = iosCapabilities;
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
  final container = await containerWithPreferences(
    {},
    overrides: [
      matrixClientProvider.overrideWithValue(client ?? buildTestClient()),
      fixedDeliveryMode(mode),
      if (capabilities != null)
        platformCapabilitiesProvider.overrideWithValue(capabilities),
      ...overrides,
    ],
  );

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
  Future<PushDiagnosticsInputs> load(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async => PushDiagnosticsInputs(
    capabilities: capabilities,
    now: DateTime(2026, 10, 2),
    appVersion: '1.2.0 (build 2)',
  );

  @override
  Future<List<RecentPush>> recentPushes(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async => const [];

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
    installFakePermissions();
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Delivery'),
    );
    expect(
      (row.subtitle! as Text).data,
      NotificationDeliveryMode.backgroundService.label,
    );
  });

  testWidgets('the transport rows sit behind Delivery, on the delivery page', (
    tester,
  ) async {
    installFakePermissions();
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);
    for (final row in [
      'Delivery method',
      'Unrestricted battery usage',
      'Background data',
      'Status',
    ]) {
      expect(find.text(row), findsNothing, reason: row);
    }

    await tester.tap(find.widgetWithText(ListTile, 'Delivery'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDeliveryPage), findsOneWidget);
    expect(find.text('Delivery method'), findsOneWidget);
  });

  testWidgets('with notifications off there are no Delivery or full-screen '
      'call rows', (tester) async {
    installFakePermissions(onCheck: permissionDenied);
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Delivery'), findsNothing);
    expect(find.text('Full-screen call alerts'), findsNothing);
  });

  testWidgets('with notifications on both rows are there', (tester) async {
    installFakePermissions();
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
    expect(find.text('Full-screen call alerts'), findsOneWidget);
  });

  testWidgets('with push diagnostics a Diagnostics row opens the diagnostics, '
      'the only way to Push target', (tester) async {
    await _pumpPage(
      tester,
      NotificationDeliveryMode.apns,
      capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: true),
      overrides: [
        pushDiagnosticsSourceProvider.overrideWithValue(_DiagnosticsSource()),
      ],
    );
    expect(find.widgetWithText(ListTile, 'Push target'), findsNothing);

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.byType(PushDiagnosticsPage), findsOneWidget);
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
        installFakePermissions();
        await _pumpPage(tester, mode, capabilities: androidCapabilities);

        expect(subtitle(tester), 'Calls can ring full screen');
        expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
      });
    }

    testWidgets('with background sync also says where its status shows', (
      tester,
    ) async {
      installFakePermissions();
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
      installFakePermissions(onCheck: permissionDenied);
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
    installFakePermissions();
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
    late PusherRecordingClient client;

    setUp(() {
      client = PusherRecordingClient();
      _useApplePush(client);
    });

    Future<ProviderContainer> pumpApplePush(
      WidgetTester tester, {
      ApnsStatus status = ApnsStatus.ready,
      bool granted = true,
      List<Override> overrides = const [],
    }) {
      apnsDeliveryProvider
        ..status.value = status
        ..dropped.value = 0;
      installFakePermissions(
        onCheck: granted ? permissionGranted : permissionDenied,
      );
      return _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
        client: client,
        overrides: overrides,
      );
    }

    Finder retry() => find.widgetWithText(TextButton, 'Retry');

    testWidgets('there is no Delivery or Full-screen call alerts row', (
      tester,
    ) async {
      await pumpApplePush(tester);

      expect(find.widgetWithText(ListTile, 'Delivery'), findsNothing);
      expect(find.byIcon(Icons.cloud_sync_outlined), findsNothing);
      expect(find.text('Full-screen call alerts'), findsNothing);
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

    testWidgets('a refused registration shows on the first card, and Retry '
        'registers this device again', (tester) async {
      const message = 'Could not set up notifications on this device';
      await pumpApplePush(tester, status: ApnsStatus.pusherFailed);

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
      expect(find.text(message), findsNothing);
      expect(retry(), findsNothing);
    });

    testWidgets('a working registration shows no problem', (tester) async {
      await pumpApplePush(tester);

      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(retry(), findsNothing);
    });

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
  });

  testWidgets('iOS has no vibration switches, only sounds', (tester) async {
    await _pumpPage(
      tester,
      NotificationDeliveryMode.apns,
      capabilities: iosCapabilities,
    );

    expect(find.text('Vibrate for calls'), findsNothing);
    expect(find.text('Vibrate for messages'), findsNothing);
    expect(find.text('Sounds & vibration'), findsNothing);
    expect(find.text('Sounds'), findsOneWidget);
    expect(find.text('Ringtone'), findsOneWidget);
    expect(find.text('Message tone'), findsOneWidget);
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

  group('the Enable notifications switch', () {
    late RecordedMethodCalls native;
    late FakePermissions permissions;

    setUp(() {
      native = installFakeCallsChannel();
      permissions = installFakePermissions();
    });

    testWidgets('turned off, opens the notification settings, not app info', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable notifications'),
      );
      await tester.pump();

      expect(native.methods, contains('openNotificationSettings'));
      expect(permissions.calls, isNot(contains('openAppSettings')));
    });
  });

  group('a silenced chat channel', () {
    late RecordedMethodCalls native;

    setUp(() {
      native = installFakeCallsChannel();
      installFakePermissions();
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

      final open = native.named('openChannelSettings').single;
      expect((open.arguments as Map)['channelId'], 'group_messages');
    });

    testWidgets('shows nothing while every chat channel can alert', (
      tester,
    ) async {
      installFakeLocalNotifications().deviceChannels = [
        deviceChannel('group_messages', name: 'Room messages', importance: 4),
      ];
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(find.textContaining('are silenced'), findsNothing);
    });
  });

  group('asking for the permission', () {
    late FakePermissions permissions;
    late RecordedMethodCalls backgroundSync;

    setUp(() {
      permissions = installFakePermissions(onCheck: permissionDenied);
      backgroundSync = recordMethodChannel('zuno/background_sync');
    });

    Finder toggle() =>
        find.widgetWithText(SwitchListTile, 'Enable notifications');

    testWidgets('turning it on asks, and a yes brings the delivery rows and '
        'restarts background sync', (tester) async {
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);
      expect(find.widgetWithText(ListTile, 'Delivery'), findsNothing);

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(permissions.calls, contains('requestPermissions'));
      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
      expect(backgroundSync.methods, ['startBackgroundSyncService']);
    });

    testWidgets('a no keeps it off and says nothing is delivered', (
      tester,
    ) async {
      permissions.onRequest = permissionDenied;
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      expect(find.textContaining('nothing is delivered'), findsOneWidget);
      expect(backgroundSync.methods, isEmpty);
    });

    testWidgets('with push delivery a yes leaves background sync alone', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      expect(backgroundSync.methods, isEmpty);
    });

    testWidgets('coming back from system settings picks up the change', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);
      permissions.onCheck = permissionGranted;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      expect(backgroundSync.methods, ['startBackgroundSyncService']);
    });

    testWidgets('closing the page mid-check is harmless', (tester) async {
      permissions.checkGate = Completer();
      await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

      await tester.pumpWidget(const SizedBox());
      permissions.checkGate!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('full-screen call alerts', () {
    late RecordedMethodCalls native;

    setUp(() {
      native = installFakeCallsChannel(
        reply: (call) => call.method == 'canUseFullScreenIntent' ? false : null,
      );
    });

    testWidgets('when turned off say so and open the setting', (tester) async {
      installFakePermissions();
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

      expect(native.methods, contains('openFullScreenIntentSettings'));
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
    late PusherRecordingClient client;

    setUp(() {
      client = PusherRecordingClient();
      _useApplePush(client);
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

    testWidgets('offers three levels with Name and message chosen, and no '
        'suggestion on a fixed iOS version', (tester) async {
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
      expect(find.text('Use Name only'), findsNothing);
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
  });
}
