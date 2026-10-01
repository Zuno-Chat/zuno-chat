import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/live_isolate_route.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/push/headless_decline_hold.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/hybrid_fake_async.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordedNotifications notifications;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
  });

  tearDown(() {
    CallNotificationService.instance.releaseDeclinePort();
    IsolateNameServer.removePortNameMapping(declinePortName);
  });

  test(
    'returns immediately when another isolate already holds the port',
    () async {
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
      expect(
        await CallNotificationService.instance.claimDeclinePortUnlessLive(),
        isTrue,
      );
      final runner = HeadlessPushRunner();

      final stopwatch = Stopwatch()..start();
      await awaitHeadlessDecline(runner).timeout(const Duration(seconds: 2));
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    },
  );

  test(
    'keeps waiting while the ring is up, then ends once it is taken down',
    () async {
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
      await const AndroidIncomingCallPresenter().showIncoming(
        callerName: 'Bob',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: 'call1',
      );
      notifications.active = [ringNotificationOnScreen()];
      final runner = HeadlessPushRunner();
      final time = FakeAsync();

      var completed = false;
      time.run((_) {
        awaitHeadlessDecline(runner).whenComplete(() => completed = true);
      });

      await time.advance(const Duration(seconds: 10));
      expect(
        completed,
        isFalse,
        reason: 'the hold ended while the ring notification was still up',
      );

      notifications.active = const [];
      await time.advance(declineGrace);
      expect(
        completed,
        isFalse,
        reason: 'the grace after the ring had not run',
      );

      await time.advance(declinePollEvery);
      expect(completed, isTrue);
      expect(CallNotificationService.instance.stillHoldsDeclinePort(), isFalse);
    },
  );

  test('takes over a decline route its isolate left behind when it went '
      'away, so a Decline still reaches a client', () async {
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    final gone = ReceivePort();
    addTearDown(gone.close);
    IsolateNameServer.removePortNameMapping(declinePortName);
    IsolateNameServer.registerPortWithName(gone.sendPort, declinePortName);
    final time = FakeAsync();

    time.run((_) {
      awaitHeadlessDecline(
        HeadlessPushRunner(),
        presenter: _CountingPresenter(),
      );
    });
    await time.advance(const Duration(seconds: 3));

    expect(CallNotificationService.instance.stillHoldsDeclinePort(), isTrue);
  });

  test('looks at the ring every few seconds, not every second', () async {
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    final presenter = _CountingPresenter();
    final time = FakeAsync();

    time.run((_) {
      awaitHeadlessDecline(HeadlessPushRunner(), presenter: presenter);
    });
    await time.advance(const Duration(seconds: 30));

    expect(presenter.looks, lessThanOrEqualTo(10));
    expect(presenter.looks, greaterThanOrEqualTo(9));
  });

  test('a Decline that lands just after the ring went away is still '
      'declined, since the notification goes before its action engine '
      'boots', () async {
    final sent = <Map<String, Object?>>[];
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    await const AndroidIncomingCallPresenter().showIncoming(
      callerName: 'Bob',
      callerId: '@bob:example.org',
      isVideo: false,
      roomId: '!room:example.org',
      callId: 'call1',
    );
    notifications.active = [ringNotificationOnScreen()];
    final runner = HeadlessPushRunner()..liveClient = _clientSending(sent);
    final time = FakeAsync();

    var completed = false;
    time.run((_) {
      awaitHeadlessDecline(runner).whenComplete(() => completed = true);
    });
    await time.advance(const Duration(seconds: 2));
    notifications.active = const [];
    await time.advance(const Duration(seconds: 3));
    expect(completed, isFalse);
    expect(CallNotificationService.instance.stillHoldsDeclinePort(), isTrue);

    CallNotificationService.instance.onHeadlessDeclineForTest(
      const HeadlessCallDecline(roomId: '!room:example.org', callId: 'call1'),
    );
    await time.settle();

    expect(completed, isTrue);
    expect(sent.single['call_id'], 'call1');
    expect(await isCallResolved('call1'), isTrue);
  });

  test('a ring that comes back during the grace keeps the hold', () async {
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    notifications.active = const [];
    final time = FakeAsync();

    var completed = false;
    time.run((_) {
      awaitHeadlessDecline(HeadlessPushRunner())
          .whenComplete(() => completed = true);
    });
    await time.advance(const Duration(seconds: 3));
    await const AndroidIncomingCallPresenter().showIncoming(
      callerName: 'Bob',
      callerId: '@bob:example.org',
      isVideo: false,
      roomId: '!room:example.org',
      callId: 'call1',
    );
    notifications.active = [ringNotificationOnScreen()];
    await time.advance(const Duration(seconds: 10));

    expect(completed, isFalse);

    await time.advance(const Duration(seconds: 35));
    expect(completed, isTrue, reason: 'a ring never outlives its 45 seconds');
  });

  test('a decline handed to the hold is reported done once it went out, so '
      'the action engine never declines it twice', () async {
    final sent = <Map<String, Object?>>[];
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    await const AndroidIncomingCallPresenter().showIncoming(
      callerName: 'Bob',
      callerId: '@bob:example.org',
      isVideo: false,
      roomId: '!room:example.org',
      callId: 'call1',
    );
    notifications.active = [ringNotificationOnScreen()];
    final runner = HeadlessPushRunner()..liveClient = _clientSending(sent);

    final hold = awaitHeadlessDecline(runner);
    final handed = await handOffToLiveIsolate(declinePortName, {
      'roomId': '!room:example.org',
      'callId': 'call1',
    });
    await hold.timeout(const Duration(seconds: 5));

    expect(handed, isTrue);
    expect(sent.single['call_id'], 'call1');
  });

  test('a decline the hold cannot send because the app took the client goes '
      'to the app, and is reported done only then', () async {
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async => throw const ClientLeaseDenied();
    final hold = awaitHeadlessDecline(runner);
    await pumpEventQueue();

    final app = ReceivePort();
    addTearDown(app.close);
    final taken = <Map<Object?, Object?>>[];
    app.listen((message) {
      if (answerPing(message)) return;
      final route = LiveRouteMessage.from(message)!;
      taken.add(route.body);
      route
        ..accept()
        ..finish();
    });
    IsolateNameServer.removePortNameMapping(declinePortName);
    IsolateNameServer.registerPortWithName(app.sendPort, declinePortName);

    final sender = ReceivePort();
    addTearDown(sender.close);
    final replies = <Object?>[];
    sender.listen(replies.add);
    CallNotificationService.instance.onHeadlessDeclineForTest(
      HeadlessCallDecline(
        roomId: '!room:example.org',
        callId: 'call1',
        route: LiveRouteMessage.from({'replyTo': sender.sendPort}),
      ),
    );
    await hold.timeout(const Duration(seconds: 8));
    await pumpEventQueue();

    expect(taken.single['callId'], 'call1');
    expect(replies, contains('done'));
  });

  group('once Decline is tapped', () {
    late RecordedCallStyleCalls callStyle;

    setUp(() async {
      callStyle = installFakeCallStyleChannel();
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    Future<void> ringFor(String callId) async {
      await const AndroidIncomingCallPresenter().showIncoming(
        callerName: 'Bob',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: callId,
      );
      notifications.active = [ringNotificationOnScreen()];
    }

    Future<void> declineWhileHolding(
      String callId, {
      Future<void> Function()? meanwhile,
    }) async {
      final hold = awaitHeadlessDecline(HeadlessPushRunner());
      await meanwhile?.call();
      CallNotificationService.instance.onHeadlessDeclineForTest(
        HeadlessCallDecline(roomId: '!room:example.org', callId: callId),
      );
      await hold.timeout(const Duration(seconds: 3));
    }

    Future<String?> rememberedCallId() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return readRingingCall(prefs)?.callId;
    }

    test('takes the declined call\'s ring down', () async {
      await ringFor('call1');

      await declineWhileHolding('call1');

      expect(
        callStyle.calls.map((c) => c.method),
        contains('cancelIncomingCallStyle'),
      );
      expect(await rememberedCallId(), isNull);
    });

    test('leaves ringing a newer call that arrived while the decline was on '
        'its way', () async {
      await ringFor('call1');

      await declineWhileHolding(
        'call1',
        meanwhile: () async {
          await ringFor('call2');
          callStyle.clear();
        },
      );

      expect(
        callStyle.calls.map((c) => c.method),
        isNot(contains('cancelIncomingCallStyle')),
      );
      expect(await rememberedCallId(), 'call2');
    });
  });

  test('opens no client unless Decline is actually tapped', () async {
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        throw StateError('should not be reached');
      };
    final time = FakeAsync();

    var completed = false;
    time.run((_) {
      awaitHeadlessDecline(runner).whenComplete(() => completed = true);
    });
    await time.advance(declineGrace + declinePollEvery);

    expect(completed, isTrue);
    expect(builds, 0);
  });
}

class _CountingPresenter implements IncomingCallPresenter {
  int looks = 0;

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
  }) async => RingOutcome.shown;

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {}

  @override
  Future<RingingCallInfo?> activeRing() async {
    looks++;
    return (
      roomId: '!room:example.org',
      callId: 'call1',
      callerId: '@bob:example.org',
      isVideo: false,
    );
  }
}

Client _clientSending(List<Map<String, Object?>> sent) {
  final client = buildTestClient(
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
  return client;
}
