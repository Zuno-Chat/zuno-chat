import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/push_delivery_log.dart';
import 'package:zuno/core/push/pusher_info.dart';
import 'package:zuno/core/push/unified_push_pusher.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/push_target_status_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/platform_capabilities.dart';

const _apnsToken =
    'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
const _apnsPushkey = 'obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=';

class _NoopPusherClient extends Client {
  _NoopPusherClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {}
}

class _PushersClient extends Client {
  _PushersClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  @override
  String? get deviceID => 'HERE';

  List<Map<String, Object?>> pushers = [];
  Object? listError;
  Completer<void>? listGate;
  int listReads = 0;
  final deleted = <String>[];
  final refused = <String>{};

  @override
  Future<Map<String, Object?>> request(
    RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    if (type != RequestType.GET || action != '/client/v3/pushers') {
      throw StateError('unexpected request $action');
    }
    listReads++;
    await listGate?.future;
    final error = listError;
    if (error != null) throw error;
    return {'pushers': pushers};
  }

  @override
  Future<void> deletePusher(PusherId pusher) async {
    if (refused.contains(pusher.pushkey)) throw Exception('refused');
    deleted.add(pusher.pushkey);
    pushers.removeWhere((p) => p['pushkey'] == pusher.pushkey);
  }

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {}
}

Map<String, Object?> _pusherJson({
  required String appId,
  required String pushkey,
  String appName = '',
  String deviceName = '',
  String? url,
  String? deviceId,
}) => {
  'app_id': appId,
  'pushkey': pushkey,
  'app_display_name': appName,
  'device_display_name': deviceName,
  'kind': 'http',
  'lang': 'en',
  'data': {'url': ?url, 'format': 'event_id_only'},
  'device_id': ?deviceId,
};

class _FixedDeliveryModeNotifier extends NotificationDeliveryModeNotifier {
  _FixedDeliveryModeNotifier(this._mode);
  final NotificationDeliveryMode _mode;

  @override
  NotificationDeliveryMode build() => _mode;
}

class _DistributorUnifiedPush extends FakeUnifiedPush {
  String? distributor;
  Object? unregisterError;

  @override
  Future<String?> getDistributor() async => distributor;

  @override
  Future<void> unregister(String instance) async {
    final error = unregisterError;
    if (error != null) throw error;
  }
}

PusherInfo _pusher({required String appId, required String pushkey}) =>
    PusherInfo(
      appId: appId,
      pushkey: pushkey,
      appDisplayName: 'Zuno Chat',
      deviceDisplayName: 'Zuno on Android',
      kind: 'http',
      lang: 'en',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fcmDeliveryProvider
      ..availabilityReader = (() async => FcmAvailability.available)
      ..tokenReader = (() async => 'fcm-token-abc')
      ..tokenDeleter = (() async {});
    await fcmDeliveryProvider.registerNow(_NoopPusherClient());
  });

  tearDown(() async {
    await fcmDeliveryProvider.stop(_NoopPusherClient());
    unifiedPushDeliveryProvider.lastPusherError = null;
  });

  test('in fcm mode this session is identified by its registration token', () {
    expect(currentPushkeyFor(NotificationDeliveryMode.fcm), 'fcm-token-abc');
  });

  test("this session's own FCM pusher is never an \"other push target\"", () {
    final groups = groupPushers([
      _pusher(appId: fcmAppId, pushkey: 'fcm-token-abc'),
      _pusher(appId: 'org.example.other', pushkey: 'someone-else'),
    ], currentPushkeyFor(NotificationDeliveryMode.fcm));

    expect(groups.currentSession?.pushkey, 'fcm-token-abc');
    expect(groups.others.single.pushkey, 'someone-else');
  });

  test('a transport with nothing registered claims no pusher as its own', () {
    expect(
      currentPushkeyFor(NotificationDeliveryMode.backgroundService),
      isNull,
    );
    final groups = groupPushers([
      _pusher(appId: fcmAppId, pushkey: 'fcm-token-abc'),
    ], currentPushkeyFor(NotificationDeliveryMode.backgroundService));
    expect(groups.currentSession, isNull);
  });

  test('the last error shown is the running transport, not the other one', () {
    unifiedPushDeliveryProvider.lastPusherError = 'ntfy refused the endpoint';

    expect(lastPusherErrorFor(NotificationDeliveryMode.fcm), isNull);
    expect(
      lastPusherErrorFor(NotificationDeliveryMode.unifiedPush),
      'ntfy refused the endpoint',
    );
  });

  group('Apple push', () {
    tearDown(() async {
      await apnsDeliveryProvider.stop(_NoopPusherClient());
      apnsDeliveryProvider.lastPusherError = null;
    });

    test('this session is identified by its device token, and its pusher is '
        'never an "other push target"', () async {
      ambientCapabilities = iosCapabilities;
      apnsDeliveryProvider
        ..tokenReader = (() async => _apnsToken)
        ..notificationsAllowed = (() async => true);
      await apnsDeliveryProvider.registerNow(_NoopPusherClient());

      final groups = groupPushers([
        _pusher(appId: apnsAppId, pushkey: _apnsPushkey),
        _pusher(appId: fcmAppId, pushkey: 'fcm-token-abc'),
      ], currentPushkeyFor(NotificationDeliveryMode.apns));

      expect(groups.currentSession?.pushkey, _apnsPushkey);
      expect(groups.others.single.appId, fcmAppId);
    });

    test('its last error is shown, not the Android one', () {
      apnsDeliveryProvider.lastPusherError = 'M_FORBIDDEN';

      expect(lastPusherErrorFor(NotificationDeliveryMode.apns), 'M_FORBIDDEN');
      expect(lastPusherErrorFor(NotificationDeliveryMode.fcm), isNull);
    });
  });

  group('the page', () {
    late _PushersClient client;
    late _DistributorUnifiedPush unifiedPush;

    setUp(() {
      client = _PushersClient();
      unifiedPush = _DistributorUnifiedPush();
      UnifiedPushPlatform.instance = unifiedPush;
    });

    tearDown(() {
      fcmDeliveryProvider
        ..lastPusherError = null
        ..removed.value = false;
      unifiedPushDeliveryProvider
        ..savedDistributor = null
        ..removed.value = false;
    });

    Future<void> pumpPage(
      WidgetTester tester,
      NotificationDeliveryMode mode, {
      bool settle = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          matrixClientProvider.overrideWithValue(client),
          notificationDeliveryModeProvider.overrideWith(
            () => _FixedDeliveryModeNotifier(mode),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PushTargetStatusPage(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    String detail(WidgetTester tester, String label) {
      final row = find.widgetWithText(ListTile, label);
      return tester
          .widget<SelectableText>(
            find.descendant(of: row, matching: find.byType(SelectableText)),
          )
          .data!;
    }

    Future<void> confirmRemove(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
    }

    group('this device', () {
      testWidgets('shows what the server holds for it', (tester) async {
        client.pushers = [
          _pusherJson(
            appId: fcmAppId,
            pushkey: 'fcm-token-abc',
            appName: 'Zuno',
            deviceName: 'Zuno on Android',
            url: 'https://matrix.example.org/_matrix/push/v1/notify',
            deviceId: 'SERVERSIDE',
          ),
        ];
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(detail(tester, 'App ID'), fcmAppId);
        expect(detail(tester, 'Push key'), 'fcm-token-abc');
        expect(detail(tester, 'App display name'), 'Zuno');
        expect(detail(tester, 'Device name'), 'Zuno on Android');
        expect(detail(tester, 'Device ID'), 'SERVERSIDE');
        expect(
          detail(tester, 'Push gateway URL'),
          'https://matrix.example.org/_matrix/push/v1/notify',
        );
        expect(detail(tester, 'Format'), 'event_id_only');
        expect(find.text('Distributor'), findsNothing);
        expect(find.text('Using the public push bridge'), findsNothing);
      });

      testWidgets('without a server entry it falls back to what this device '
          'knows', (tester) async {
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(detail(tester, 'App ID'), '—');
        expect(detail(tester, 'Push key'), 'fcm-token-abc');
        expect(detail(tester, 'Device ID'), 'HERE');
        expect(
          detail(tester, 'Push gateway URL'),
          'https://matrix.example.org/_matrix/push/v1/notify',
        );
      });

      testWidgets('a registration through the public bridge says what that '
          'bridge sees', (tester) async {
        client.pushers = [
          _pusherJson(
            appId: fcmAppId,
            pushkey: 'fcm-token-abc',
            url:
                'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify',
          ),
        ];
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.text('Using the public push bridge'), findsOneWidget);
        expect(find.textContaining('never sees who sent it'), findsOneWidget);
      });

      testWidgets('the last error is shown', (tester) async {
        fcmDeliveryProvider.lastPusherError = 'M_FORBIDDEN';
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Last error'),
            matching: find.text('M_FORBIDDEN'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('UnifiedPush names the distributor', (tester) async {
        unifiedPush.distributor = 'io.heckel.ntfy';
        await pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        expect(detail(tester, 'Distributor'), 'ntfy');
        expect(find.text('Recent pushes'), findsNothing);
      });

      testWidgets('UnifiedPush without a distributor says None', (
        tester,
      ) async {
        await pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        expect(detail(tester, 'Distributor'), 'None');
      });

      testWidgets('closing the page mid-load is harmless', (tester) async {
        client.listGate = Completer();
        await pumpPage(tester, NotificationDeliveryMode.fcm, settle: false);

        await tester.pumpWidget(const SizedBox());
        client.listGate!.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });

    group('recent pushes', () {
      String line({
        required DateTime received,
        DateTime? sent,
        String original = 'high',
        String delivered = 'high',
        bool idle = false,
        int? bucket,
      }) => [
        received.millisecondsSinceEpoch,
        sent?.millisecondsSinceEpoch ?? '',
        original,
        delivered,
        idle ? '1' : '0',
        bucket ?? '',
      ].join('\t');

      testWidgets('says None yet before any arrive', (tester) async {
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Recent pushes'),
              matching: find.byType(Column),
            ),
            matching: find.text('None yet'),
          ),
          findsWidgets,
        );
      });

      testWidgets('lists the last ten, marking the late ones', (tester) async {
        final now = DateTime.now();
        final received = now.subtract(const Duration(minutes: 1));
        SharedPreferences.setMockInitialValues({
          pushDeliveryLogKey: [
            line(
              received: received,
              sent: received.subtract(const Duration(seconds: 2)),
            ),
            line(
              received: received,
              sent: received.subtract(const Duration(minutes: 5)),
              idle: true,
              bucket: 45,
            ),
            line(received: received, delivered: 'normal'),
            for (var i = 0; i < 9; i++) line(received: received),
          ].join('\n'),
        });
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.text('Arrived after 2 s, high priority'), findsOneWidget);
        expect(
          find.text(
            'Arrived after 5 min, high priority, device asleep, standby '
            'bucket restricted',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Arrived, lowered to normal priority'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.schedule_outlined), findsNWidgets(2));
        expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(8));
      });

      testWidgets('an older push is labeled with its day', (tester) async {
        final received = DateTime.now().subtract(const Duration(days: 1));
        SharedPreferences.setMockInitialValues({
          pushDeliveryLogKey: line(received: received),
        });
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.textContaining('Yesterday, '), findsOneWidget);
      });
    });

    group('other registrations', () {
      void twoOthers() => client.pushers = [
        _pusherJson(appId: fcmAppId, pushkey: 'fcm-token-abc'),
        _pusherJson(
          appId: 'org.example.app',
          pushkey: 'tablet-key',
          deviceName: 'Tablet',
          url: 'https://push.example.org/notify',
        ),
        _pusherJson(appId: unifiedPushAppId, pushkey: 'laptop-key'),
      ];

      testWidgets('are listed by name, falling back to the app ID', (
        tester,
      ) async {
        twoOthers();
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.text('Tablet'), findsOneWidget);
        expect(
          find.text('org.example.app\nhttps://push.example.org/notify'),
          findsOneWidget,
        );
        expect(find.text(unifiedPushAppId), findsOneWidget);
        expect(find.text('$unifiedPushAppId\nlaptop-key'), findsOneWidget);
      });

      testWidgets('an app name is used when there is no device name', (
        tester,
      ) async {
        client.pushers = [
          _pusherJson(appId: 'org.example.app', pushkey: 'k', appName: 'Mail'),
        ];
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.text('Mail'), findsOneWidget);
      });

      testWidgets('say Loading… until the server answers', (tester) async {
        client.listGate = Completer();
        await pumpPage(tester, NotificationDeliveryMode.fcm, settle: false);
        await tester.pump();

        expect(find.text('Loading…'), findsWidgets);

        client.listGate!.complete();
        await tester.pumpAndSettle();

        expect(find.text('Loading…'), findsNothing);
        expect(find.text('None'), findsOneWidget);
        expect(find.text('Remove all'), findsNothing);
      });

      testWidgets('a failed read says so instead of None', (tester) async {
        client.listError = Exception('offline');
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        expect(find.text('None'), findsNothing);
        expect(
          find.text('Could not load. Pull down to try again.'),
          findsOneWidget,
        );
      });

      testWidgets('pulling down reads them again', (tester) async {
        await pumpPage(tester, NotificationDeliveryMode.fcm);
        twoOthers();

        await tester.fling(
          find.text('This device'),
          const Offset(0, 1500),
          1000,
        );
        await tester.pumpAndSettle();

        expect(client.listReads, 2);
        expect(find.text('Tablet'), findsOneWidget);
      });

      testWidgets('one can be removed after asking', (tester) async {
        twoOthers();
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Tablet'),
            matching: find.byTooltip('Remove'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove this push target?'), findsOneWidget);
        expect(find.textContaining('"Tablet" stops receiving'), findsOneWidget);

        await confirmRemove(tester);

        expect(client.deleted, ['tablet-key']);
        expect(find.text('Tablet'), findsNothing);
        expect(find.text(unifiedPushAppId), findsOneWidget);
      });

      testWidgets('Cancel removes nothing', (tester) async {
        twoOthers();
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(find.text('Remove all'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(client.deleted, isEmpty);
      });

      testWidgets('all of them can go at once, never this device', (
        tester,
      ) async {
        twoOthers();
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(find.text('Remove all'));
        await tester.pumpAndSettle();
        expect(find.text('Remove 2 push targets?'), findsOneWidget);

        await confirmRemove(tester);

        expect(client.deleted, ['tablet-key', 'laptop-key']);
        expect(find.text('None'), findsOneWidget);
        expect(detail(tester, 'App ID'), fcmAppId);
      });

      testWidgets('a single other one is asked about as one', (tester) async {
        client.pushers = [
          _pusherJson(appId: 'org.example.app', pushkey: 'tablet-key'),
        ];
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(find.text('Remove all'));
        await tester.pumpAndSettle();

        expect(find.text('Remove this push target?'), findsOneWidget);
      });

      testWidgets('a refused removal says so', (tester) async {
        twoOthers();
        client.refused.add('tablet-key');
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        await tester.tap(find.text('Remove all'));
        await tester.pumpAndSettle();
        await confirmRemove(tester);

        expect(client.deleted, ['laptop-key']);
        expect(find.text('Tablet'), findsOneWidget);
        expect(find.text('Not removed. Try again.'), findsOneWidget);
      });
    });

    group('removing this device', () {
      Future<void> startRemoving(WidgetTester tester) async {
        await tester.tap(find.text('Remove push target'));
        await tester.pumpAndSettle();
      }

      testWidgets('with Google services it drops the token and leaves', (
        tester,
      ) async {
        await pumpPage(tester, NotificationDeliveryMode.fcm);
        expect(
          find.textContaining("drops this device's registration token"),
          findsOneWidget,
        );

        await startRemoving(tester);
        expect(find.text('Remove push target?'), findsOneWidget);
        expect(find.textContaining('registration token is dropped'), findsOne);

        await confirmRemove(tester);

        expect(client.deleted, ['fcm-token-abc']);
        expect(fcmDeliveryProvider.token, isNull);
        expect(fcmDeliveryProvider.removed.value, isTrue);
        expect(find.byType(PushTargetStatusPage), findsNothing);
      });

      for (final (mode, detail) in [
        (
          NotificationDeliveryMode.fcm,
          "The server forgets this device, and this device's registration "
              'token is dropped.',
        ),
        (
          NotificationDeliveryMode.unifiedPush,
          'The server forgets this device, and the distributor registration '
              'is dropped.',
        ),
      ]) {
        testWidgets('with ${mode.name} the warning says a restart registers '
            'it again too', (tester) async {
          await pumpPage(tester, mode);

          await startRemoving(tester);

          expect(
            find.text(
              'This device stops receiving notifications until you register '
              'again or Zuno restarts. $detail',
            ),
            findsOneWidget,
          );
        });
      }

      testWidgets('Cancel keeps it', (tester) async {
        await pumpPage(tester, NotificationDeliveryMode.fcm);

        await startRemoving(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(client.deleted, isEmpty);
        expect(fcmDeliveryProvider.removed.value, isFalse);
        expect(find.byType(PushTargetStatusPage), findsOneWidget);
      });

      testWidgets('with UnifiedPush it unregisters from the distributor too', (
        tester,
      ) async {
        await pumpPage(tester, NotificationDeliveryMode.unifiedPush);
        expect(
          find.textContaining('unregisters from the distributor'),
          findsOneWidget,
        );

        await startRemoving(tester);
        expect(
          find.textContaining('distributor registration is dropped'),
          findsOneWidget,
        );
        await confirmRemove(tester);

        expect(unifiedPushDeliveryProvider.removed.value, isTrue);
        expect(find.byType(PushTargetStatusPage), findsNothing);
      });

      testWidgets('a failure says so and stays', (tester) async {
        unifiedPush.unregisterError = PlatformException(code: 'gone');
        await pumpPage(tester, NotificationDeliveryMode.unifiedPush);

        await startRemoving(tester);
        await confirmRemove(tester);

        expect(tester.takeException(), isNull);
        expect(unifiedPushDeliveryProvider.removed.value, isFalse);
        expect(find.byType(PushTargetStatusPage), findsOneWidget);
        expect(find.text('Not removed. Try again.'), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(
                find.widgetWithText(ListTile, 'Remove push target'),
              )
              .onTap,
          isNotNull,
        );
      });

      testWidgets('with Apple push the server forgets it', (tester) async {
        await pumpPage(tester, NotificationDeliveryMode.apns);
        expect(
          find.text('Makes the server forget this device'),
          findsOneWidget,
        );

        await startRemoving(tester);
        expect(
          find.textContaining('The server forgets this device.'),
          findsOne,
        );
        await confirmRemove(tester);

        expect(find.byType(PushTargetStatusPage), findsNothing);
      });

      testWidgets('with background sync there is nothing to remove', (
        tester,
      ) async {
        await pumpPage(tester, NotificationDeliveryMode.backgroundService);
        expect(
          find.text('Nothing is registered for background sync'),
          findsOneWidget,
        );
        expect(find.text('Push gateway URL'), findsOneWidget);
        expect(detail(tester, 'Push gateway URL'), '—');

        await startRemoving(tester);
        expect(
          find.textContaining('Background sync has nothing registered'),
          findsOneWidget,
        );
        await confirmRemove(tester);

        expect(find.byType(PushTargetStatusPage), findsNothing);
      });
    });
  });
}
