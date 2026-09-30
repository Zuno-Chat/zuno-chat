import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';
import 'package:zuno/features/settings/presentation/notifications_settings_page.dart';

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
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      matrixClientProvider.overrideWithValue(buildTestClient()),
      notificationDeliveryModeProvider.overrideWith(
        () => _FixedDeliveryModeNotifier(mode),
      ),
      if (capabilities != null)
        platformCapabilitiesProvider.overrideWithValue(capabilities),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotificationsSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
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
      expect(find.widgetWithText(ListTile, 'Delivery'), findsOneWidget);
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
}
