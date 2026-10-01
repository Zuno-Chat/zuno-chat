import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/push/headless_decline_hold.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/hybrid_fake_async.dart';

class _ScriptedPresenter implements IncomingCallPresenter {
  RingingCallInfo? ringing;
  final shown = <String>[];
  var cancels = 0;

  @override
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
    Future<RingingCallInfo?>? ringingNow,
  }) async {
    shown.add(callId);
    ringing = (
      roomId: roomId,
      callId: callId,
      callerId: callerId,
      isVideo: isVideo,
    );
    return RingOutcome.shown;
  }

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {
    cancels++;
    ringing = null;
  }

  @override
  Future<RingingCallInfo?> activeRing() async => ringing;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = CallNotificationService.instance;
  Map<String, Object?>? initializeArguments;
  late List<Map<String, Object?>> sent;
  late Client client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    await service.initialize(claimDeclinePort: false);
    initializeArguments ??= notifications.initializeArguments;

    sent = [];
    client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.method == 'PUT' && request.url.path.contains('/send/')) {
          sent.add(jsonDecode(request.body) as Map<String, Object?>);
        }
        return http.Response(jsonEncode({'event_id': r'$decline'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    client.rooms.add(buildTestRoom(client));
  });

  tearDown(() async {
    service.releaseDeclinePort();
    await pumpEventQueue();
  });

  void tapDeclineWhileHeadless() {
    final handle = initializeArguments!['callback_handle']! as int;
    final handler =
        PluginUtilities.getCallbackFromHandle(
              CallbackHandle.fromRawHandle(handle),
            )!
            as void Function(NotificationResponse);
    handler(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'decline',
        payload: jsonEncode({
          'roomId': '!room:example.org',
          'callId': 'call1',
          'callerId': '@bob:example.org',
          'isVideo': false,
        }),
      ),
    );
  }

  Future<void> ring(IncomingCallPresenter presenter) => presenter.showIncoming(
    callerName: 'Bob',
    callerId: '@bob:example.org',
    isVideo: false,
    roomId: '!room:example.org',
    callId: 'call1',
  );

  final presenters = <String, IncomingCallPresenter Function()>{
    'the android presenter': () => const AndroidIncomingCallPresenter(),
    'the presenter that presents nothing': () =>
        const NoopIncomingCallPresenter(),
    'a scripted presenter': _ScriptedPresenter.new,
  };

  for (final MapEntry(key: name, value: build) in presenters.entries) {
    group('with $name', () {
      test(
        'the decline port is claimed, held and released as before',
        () async {
          final presenter = build();

          expect(service.stillHoldsDeclinePort(), isFalse);
          expect(await service.claimDeclinePortUnlessLive(), isTrue);

          await ring(presenter);
          await presenter.activeRing();
          await presenter.cancelIncoming();

          expect(service.stillHoldsDeclinePort(), isTrue);
          expect(await service.claimDeclinePortUnlessLive(), isFalse);
          service.releaseDeclinePort();
          expect(service.stillHoldsDeclinePort(), isFalse);
        },
      );

      test(
        'Decline tapped while headless reaches the room through the port',
        () async {
          final runner = HeadlessPushRunner()..liveClient = client;

          final hold = awaitHeadlessDecline(runner, presenter: build());
          expect(service.stillHoldsDeclinePort(), isTrue);
          tapDeclineWhileHeadless();
          await hold.timeout(const Duration(seconds: 5));

          expect(sent.single['call_id'], 'call1');
          expect(service.stillHoldsDeclinePort(), isFalse);
        },
      );
    });
  }

  test('the hold waits out a ring its presenter still shows, then has the '
      'presenter take it down after the decline', () async {
    final presenter = _ScriptedPresenter();
    await ring(presenter);
    final runner = HeadlessPushRunner()..liveClient = client;
    final time = FakeAsync();

    var held = true;
    time.run((_) {
      awaitHeadlessDecline(
        runner,
        presenter: presenter,
      ).whenComplete(() => held = false);
    });
    await time.advance(const Duration(seconds: 5));
    expect(held, isTrue);
    expect(service.stillHoldsDeclinePort(), isTrue);
    tapDeclineWhileHeadless();
    await time.settle();

    expect(held, isFalse);
    expect(sent.single['call_id'], 'call1');
    expect(presenter.cancels, 1);
    expect(service.stillHoldsDeclinePort(), isFalse);
  });

  test('with no ring presented the hold stands down, opens no client and '
      'lets the port go', () async {
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        throw StateError('should not be reached');
      };

    final time = FakeAsync();

    var held = true;
    time.run((_) {
      awaitHeadlessDecline(
        runner,
        presenter: const NoopIncomingCallPresenter(),
      ).whenComplete(() => held = false);
    });
    await time.advance(declineGrace + declinePollEvery);

    expect(held, isFalse);
    expect(builds, 0);
    expect(service.stillHoldsDeclinePort(), isFalse);
  });
}
