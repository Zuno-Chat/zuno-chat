import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/push_delivery_log.dart';
import 'package:zuno/core/push/push_diagnostics_data.dart';
import 'package:zuno/core/push/push_diagnostics_source.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

http.Response _module(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'x-zuno-push': '1', 'content-type': 'application/json'},
);

http.Response _health({required int serverTs}) => _module({
  'pushers': [
    {
      'app_id': 'im.zuno.chat.ios',
      'last_success_ts': 1789999990000,
      'failing_since_ts': null,
    },
  ],
  'voip': {
    'registered': true,
    'kid': 7,
    'last_result': 'sent',
    'last_ts': 1789999990000,
  },
  'nse': {'credential_expires_ts': 1790086400000, 'last_fetch_ts': null},
  'server_ts': serverTs,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pushDiag = MethodChannel('zuno/push_diag');
  const voip = MethodChannel('zuno/voip');
  final ios = capabilitiesLike(
    iosCapabilities,
    pushDiagnostics: true,
    voipRing: true,
    nseNotifications: true,
  );
  final askedAt = DateTime.fromMillisecondsSinceEpoch(1790000000000);
  late Future<http.Response> Function(http.Request request) answer;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Zuno',
      packageName: 'im.zuno.chat',
      version: '1.2.0',
      buildNumber: '2',
      buildSignature: '',
    );
    messenger.setMockMethodCallHandler(
      pushDiag,
      (call) async => {
        'settings': {'authorization': 'authorized'},
        'environment': 'production',
        'ledger': [
          {'state': 'ended', 'source': 'push', 'ts': 1789999990000},
        ],
      },
    );
    messenger.setMockMethodCallHandler(
      voip,
      (call) async => {
        'token': 'AAEC',
        'environment': 'production',
        'kid': 7,
        'key': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
        'callkit': true,
      },
    );
    answer = (request) async => http.Response('{}', 404);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pushDiag, null);
    messenger.setMockMethodCallHandler(voip, null);
  });

  LivePushDiagnosticsSource source() {
    final mock = MockClient((request) => answer(request));
    final client = buildTestClient(userId: '@me:example.org', httpClient: mock);
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    return LivePushDiagnosticsSource(
      client,
      httpClient: mock,
      now: () => askedAt,
    );
  }

  test('every source is read, and a server clock ahead of the device gives '
      'a positive offset', () async {
    answer = (request) async {
      if (request.url.path.endsWith('/health')) {
        return _health(serverTs: 1790000120000);
      }
      if (request.url.path.endsWith('/pushers')) {
        return http.Response(jsonEncode({'pushers': []}), 200);
      }
      return http.Response('{}', 404);
    };

    final inputs = await source().load(ios, NotificationDeliveryMode.apns);

    expect(inputs.reach, ServerReach.reachable);
    expect(inputs.health?.serverOffset, const Duration(minutes: 2));
    expect(
      inputs.health?.toDevice(
        DateTime.fromMillisecondsSinceEpoch(1790000120000),
      ),
      askedAt,
    );
    expect(inputs.health?.voipKid, 7);
    expect(inputs.health?.voipLastResult, 'sent');
    expect(inputs.snapshot.settings['authorization'], 'authorized');
    expect(inputs.snapshot.ledger, hasLength(1));
    expect(inputs.voip?.kid, 7);
    expect(inputs.voip?.hasToken, isTrue);
    expect(inputs.voip?.callKit, isTrue);
    expect(inputs.pushers, isEmpty);
    expect(inputs.appVersion, '1.2.0 (build 2)');
    expect(inputs.now, askedAt);
  });

  test('push turned off reads as turned off, a module still starting as '
      'starting', () async {
    for (final (errcode, reach) in [
      ('IM.ZUNO.PUSH_DISABLED', ServerReach.turnedOff),
      ('IM.ZUNO.STARTING', ServerReach.starting),
    ]) {
      answer = (request) async =>
          _module({'errcode': errcode, 'error': 'not now'}, status: 503);

      expect(
        (await source().load(ios, NotificationDeliveryMode.apns)).reach,
        reach,
        reason: errcode,
      );
    }
  });

  test('a server that cannot be reached reads as unreachable', () async {
    answer = (request) async => throw const SocketException('offline');

    final inputs = await source().load(ios, NotificationDeliveryMode.apns);

    expect(inputs.reach, ServerReach.unreachable);
    expect(inputs.health, isNull);
    expect(inputs.pushers, isNull);
  });

  test('a test notification is sent, rate limited or refused', () async {
    answer = (request) async =>
        _module({'event_id': r'$zuno_test_1', 'server_ts': 1});
    expect(await source().sendTest(), PushTestOutcome.sent);

    answer = (request) async => _module({
      'errcode': 'M_LIMIT_EXCEEDED',
      'error': 'slow down',
      'retry_after_ms': 1000,
    }, status: 429);
    expect(await source().sendTest(), PushTestOutcome.rateLimited);

    answer = (request) async => _module({
      'errcode': 'IM.ZUNO.NOT_PUSHER_INSTANCE',
      'error': 'elsewhere',
    }, status: 503);
    expect(await source().sendTest(), PushTestOutcome.failed);
  });

  test('a server without the push module reads as not installed', () async {
    answer = (request) async => http.Response('{}', 404);

    final inputs = await source().load(ios, NotificationDeliveryMode.apns);

    expect(inputs.reach, ServerReach.notInstalled);
  });

  test('a plain page of any status below 500 reads as not installed, a 502 '
      'as unreachable', () async {
    for (final status in [200, 403]) {
      answer = (request) async => http.Response('<html></html>', status);
      final inputs = await source().load(ios, NotificationDeliveryMode.apns);
      expect(inputs.reach, ServerReach.notInstalled, reason: '$status');
      expect(await source().sendTest(), PushTestOutcome.notAvailable);
    }

    answer = (request) async => http.Response('bad gateway', 502);
    final inputs = await source().load(ios, NotificationDeliveryMode.apns);
    expect(inputs.reach, ServerReach.unreachable);
    expect(await source().sendTest(), PushTestOutcome.failed);
  });

  test('a test on a server without the push module, or with push turned off, '
      'is not available; a broken route is a failure', () async {
    answer = (request) async => http.Response('{}', 404);
    expect(await source().sendTest(), PushTestOutcome.notAvailable);

    answer = (request) async => _module({
      'errcode': 'IM.ZUNO.PUSH_DISABLED',
      'error': 'off',
    }, status: 503);
    expect(await source().sendTest(), PushTestOutcome.notAvailable);

    answer = (request) async => http.Response('bad gateway', 502);
    expect(await source().sendTest(), PushTestOutcome.failed);
  });

  test('Apple push carries the dropped count and no Android status', () async {
    final inputs = await source().load(ios, NotificationDeliveryMode.apns);

    expect(inputs.deliveryMode, NotificationDeliveryMode.apns);
    expect(inputs.droppedRegistrations, 0);
    expect(inputs.fcmStatus, isNull);
    expect(inputs.playServices, isNull);
    expect(inputs.deliveries, isNull);
  });

  test('Google services carries its status, Google Play services and the '
      'delivery log', () async {
    const fcm = MethodChannel('zuno/fcm');
    messenger.setMockMethodCallHandler(fcm, (call) async => 'available');
    addTearDown(() => messenger.setMockMethodCallHandler(fcm, null));
    final received = DateTime.fromMillisecondsSinceEpoch(1789999990000);
    SharedPreferences.setMockInitialValues({
      pushDeliveryLogKey: [
        received.millisecondsSinceEpoch,
        '',
        'high',
        'high',
        '0',
        '',
      ].join('\t'),
    });
    fcmDeliveryProvider.status.value = FcmStatus.ready;
    addTearDown(() => fcmDeliveryProvider.status.value = FcmStatus.idle);
    final android = capabilitiesLike(
      androidCapabilities,
      pushDiagnostics: true,
    );

    final inputs = await source().load(android, NotificationDeliveryMode.fcm);

    expect(inputs.fcmStatus, FcmStatus.ready);
    expect(inputs.playServices, FcmAvailability.available);
    expect(inputs.deliveries?.single.receivedAt, received);
    expect(inputs.droppedRegistrations, isNull);
  });

  test('recent pushes come from the Apple logs, the delivery log, or '
      'nowhere', () async {
    messenger.setMockMethodCallHandler(
      pushDiag,
      (call) async => {
        'nse': {
          'log': ['2026-10-03T21:00:00.000Z nse_shown t=- ms=1 safe=0'],
        },
        'app': {
          'log': ['2026-10-03T21:01:00.000Z ring ms=4'],
        },
      },
    );
    SharedPreferences.setMockInitialValues({});

    final apple = await source().recentPushes(
      ios,
      NotificationDeliveryMode.apns,
    );
    final unified = await source().recentPushes(
      capabilitiesLike(androidCapabilities, pushDiagnostics: true),
      NotificationDeliveryMode.unifiedPush,
    );
    final fcmPushes = await source().recentPushes(
      capabilitiesLike(androidCapabilities, pushDiagnostics: true),
      NotificationDeliveryMode.fcm,
    );

    expect([for (final push in apple) push.summary], ['Call rang', 'Shown']);
    expect(unified, isEmpty);
    expect(fcmPushes, isEmpty);
  });

  test('without a homeserver the test is not sent', () async {
    final client = buildTestClient(userId: '@me:example.org');

    expect(
      await LivePushDiagnosticsSource(client).sendTest(),
      PushTestOutcome.failed,
    );
  });
}
