import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/headless_message_action_provider.dart';
import 'package:zuno/core/calls/notifications/live_isolate_route.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/message_notification_action.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late List<String> requests;
  late List<Map<String, Object?>> sent;

  const markRead = (
    kind: MessageNotificationActionKind.markRead,
    roomId: '!room:example.org',
    eventId: r'$1',
    replyText: null,
  );

  setUp(() async {
    requests = [];
    sent = [];
    client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.contains('/send/')) {
          sent.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    client.rooms.add(buildTestRoom(client));
    final container = await containerWithPreferences(
      {},
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    container.read(headlessMessageActionProvider);
  });

  test('a Reply handed to the app is sent by the app\'s own client, the one '
      'that holds the room\'s encryption session, under the transaction id it '
      'came with, so a resend from the action engine is the same '
      'message', () async {
    CallNotificationService.instance.onMessageActionForTest(
      HandedMessageAction((
        kind: MessageNotificationActionKind.reply,
        roomId: '!room:example.org',
        eventId: null,
        replyText: 'on my way',
      ), txid: 'zuno-tx-9'),
    );
    await pumpEventQueue(times: 50);

    expect(sent.single['body'], 'on my way');
    expect(
      requests.where((r) => r.contains('/send/')).single,
      endsWith('/zuno-tx-9'),
    );
  });

  test('an action handed over twice is performed once, and both hand-offs '
      'hear it is done', () async {
    const reply = (
      kind: MessageNotificationActionKind.reply,
      roomId: '!room:example.org',
      eventId: null,
      replyText: 'on my way',
    );
    final answers = ReceivePort();
    addTearDown(answers.close);
    final heard = <Object?>[];
    answers.listen(heard.add);
    HandedMessageAction handed() => HandedMessageAction(
      reply,
      route: LiveRouteMessage.from({'replyTo': answers.sendPort}),
      txid: 'zuno-tx-twice',
    );

    CallNotificationService.instance.onMessageActionForTest(handed());
    CallNotificationService.instance.onMessageActionForTest(handed());
    await pumpEventQueue(times: 50);

    expect(requests.where((r) => r.contains('/send/')), hasLength(1));
    expect(heard, ['done', 'done']);
  });

  test(
    'an action handed over again after it was done is not done twice',
    () async {
      CallNotificationService.instance.onMessageActionForTest(
        HandedMessageAction(markRead, txid: 'zuno-tx-read'),
      );
      await pumpEventQueue(times: 50);
      CallNotificationService.instance.onMessageActionForTest(
        HandedMessageAction(markRead, txid: 'zuno-tx-read'),
      );
      await pumpEventQueue(times: 50);

      expect(requests.where((r) => r.contains('read_markers')), hasLength(1));
    },
  );

  test('an action for a room this device does not know does nothing', () async {
    CallNotificationService.instance.onMessageActionForTest(
      HandedMessageAction((
        kind: MessageNotificationActionKind.markRead,
        roomId: '!unknown:example.org',
        eventId: r'$1',
        replyText: null,
      )),
    );
    await pumpEventQueue();

    expect(requests, isEmpty);
  });

  test('an action handed over from the action engine is reported done once '
      'the app performed it', () async {
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    await CallNotificationService.instance.initialize();
    addTearDown(
      () => IsolateNameServer.removePortNameMapping(messageActionPortName),
    );

    final handed = await handOffToLiveIsolate(
      messageActionPortName,
      encodeMessageAction(markRead),
    ).timeout(const Duration(seconds: 5));

    expect(handed, isTrue);
    expect(requests.single, contains('read_markers'));
  });
}
