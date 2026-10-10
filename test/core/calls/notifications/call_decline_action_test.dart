import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/call_decline.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/notifications/call_decline_action.dart';
import 'package:zuno/core/matrix/client_lease.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/recording_incoming_call_presenter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const wakeLock = MethodChannel('zuno/wake_lock');
  const roomId = '!room:example.org';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> steps;
  late List<String> tags;
  late List<Map<String, Object?>> sent;
  late List<String> sendPaths;
  late RecordingIncomingCallPresenter presenter;
  var failures = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    steps = [];
    tags = [];
    sent = [];
    sendPaths = [];
    failures = 0;
    presenter = RecordingIncomingCallPresenter();
    messenger.setMockMethodCallHandler(wakeLock, (call) async {
      final tag = (call.arguments as Map)['tag'] as String;
      tags.add(tag);
      steps.add('${call.method} ${tag.replaceFirst(RegExp(r'_\d+_\d+$'), '')}');
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(wakeLock, null));

  Client clientWithRoom({bool knowsRoom = true}) {
    final client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.method == 'PUT' && request.url.path.contains('/send/')) {
          steps.add('send');
          sendPaths.add(request.url.path);
          if (failures > 0) {
            failures--;
            return http.Response('{"errcode":"M_UNKNOWN"}', 500);
          }
          sent.add(jsonDecode(request.body) as Map<String, Object?>);
        }
        return http.Response(jsonEncode({'event_id': r'$decline'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    if (knowsRoom) client.rooms.add(buildTestRoom(client));
    return client;
  }

  Future<void> decline({
    required Future<bool> Function() handOff,
    Future<Client> Function()? clientBuilder,
    List<Duration> retryDelays = const [],
    Duration handOffPatience = const Duration(milliseconds: 50),
  }) => runHeadlessCallDecline(
    roomId: roomId,
    callId: 'call1',
    handOff: handOff,
    clientBuilder: clientBuilder ?? () async => clientWithRoom(),
    presenter: presenter,
    retryDelays: retryDelays,
    handOffPatience: handOffPatience,
    handOffRetryEvery: Duration.zero,
  );

  test('a decline the running app takes stops the ring at once, remembers '
      'the call is over and opens no client here', () async {
    var builds = 0;

    await decline(
      handOff: () async {
        steps.add('handOff');
        return true;
      },
      clientBuilder: () async {
        builds++;
        return clientWithRoom();
      },
    );

    expect(presenter.ends.single.callId, 'call1');
    expect(presenter.ends.single.roomId, roomId);
    expect(await isCallResolved('call1'), isTrue);
    expect(builds, 0);
    expect(steps, ['acquire call_decline', 'handOff', 'release call_decline']);
  });

  test('with no running app to take it, the decline goes out on a one-shot '
      'client under the wake lock', () async {
    await decline(handOff: () async => false);

    expect(sent.single['msgtype'], 'im.zuno.call_decline');
    expect(sent.single['call_id'], 'call1');
    expect(steps, [
      'acquire call_decline',
      'acquire call_decline',
      'send',
      'release call_decline',
    ]);
    expect(presenter.ends.single.callId, 'call1');
    expect(await isCallResolved('call1'), isTrue);
  });

  test('a decline sent here goes out under the one transaction id every '
      'path uses for this call, so a decline the app also sent is not posted '
      'twice', () async {
    await decline(handOff: () async => false);

    expect(sendPaths.single, endsWith('/${callDeclineTxid('call1')}'));
  });

  test('a hand-off that breaks still declines here', () async {
    await decline(handOff: () async => throw StateError('route gone'));

    expect(sent.single['call_id'], 'call1');
  });

  test('a decline the server refuses at first is tried again', () async {
    failures = 1;

    await decline(
      handOff: () async => false,
      retryDelays: const [Duration.zero],
    );

    expect(sent.single['call_id'], 'call1');
  });

  test('a room this device does not know sends nothing, and the ring is '
      'still stopped', () async {
    await decline(
      handOff: () async => false,
      clientBuilder: () async => clientWithRoom(knowsRoom: false),
    );

    expect(sent, isEmpty);
    expect(presenter.ends.single.callId, 'call1');
    expect(steps.last, 'release call_decline');
  });

  test('a client that cannot be built still lets the wake lock go', () async {
    await decline(
      handOff: () async => false,
      clientBuilder: () async => throw StateError('database locked'),
    );

    expect(steps, [
      'acquire call_decline',
      'acquire call_decline',
      'release call_decline',
    ]);
    expect(presenter.ends.single.callId, 'call1');
  });

  test('while the app holds the client, the decline goes back to the app, '
      'more patiently', () async {
    var handOffs = 0;

    await decline(
      handOff: () async {
        handOffs++;
        steps.add('handOff');
        return handOffs == 3;
      },
      clientBuilder: () async => throw const ClientLeaseDenied(),
      handOffPatience: const Duration(seconds: 6),
    );

    expect(handOffs, 3);
    expect(sent, isEmpty);
    expect(steps, [
      'acquire call_decline',
      'handOff',
      'acquire call_decline',
      'acquire call_decline',
      'handOff',
      'handOff',
      'release call_decline',
    ]);
  });

  test('a decline the app never takes back fails here, the ring still '
      'stopped and the wake lock let go', () async {
    await decline(
      handOff: () async => false,
      clientBuilder: () async => throw const ClientLeaseDenied(),
    );

    expect(sent, isEmpty);
    expect(presenter.ends.single.callId, 'call1');
    expect(steps.last, 'release call_decline');
  });

  test('each decline holds its wake lock under its own tag', () async {
    final slow = Completer<Client>();

    final first = decline(
      handOff: () async => false,
      clientBuilder: () => slow.future,
    );
    await decline(handOff: () async => false);
    slow.complete(clientWithRoom());
    await first;

    expect(tags.toSet(), hasLength(2));
    expect(tags.every((tag) => tag.startsWith('call_decline_')), isTrue);
  });
}
