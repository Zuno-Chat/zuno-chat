import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/notifications/message_notification_action.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

class _SendCapableFakeDatabaseApi extends TimelineCapableFakeDatabaseApi {
  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}
}

void main() {
  group('messageNotificationActionFrom', () {
    const payloadWithEvent =
        r'{"type":"message","roomId":"!room:example.org","eventId":"$1"}';
    const payloadNoEvent = '{"type":"message","roomId":"!room:example.org"}';

    test('parses a mark_read action with its event id', () {
      final action = messageNotificationActionFrom(
        actionId: 'mark_read',
        payload: payloadWithEvent,
      );

      expect(action?.kind, MessageNotificationActionKind.markRead);
      expect(action?.roomId, '!room:example.org');
      expect(action?.eventId, r'$1');
      expect(action?.replyText, isNull);
    });

    test('parses a reply action with the typed text', () {
      final action = messageNotificationActionFrom(
        actionId: 'reply',
        payload: payloadWithEvent,
        input: 'on my way',
      );

      expect(action?.kind, MessageNotificationActionKind.reply);
      expect(action?.roomId, '!room:example.org');
      expect(action?.eventId, r'$1');
      expect(action?.replyText, 'on my way');
    });

    test(
      'a reply with no eventId still parses — only Mark-as-read needs one',
      () {
        final action = messageNotificationActionFrom(
          actionId: 'reply',
          payload: payloadNoEvent,
          input: 'hey',
        );

        expect(action?.kind, MessageNotificationActionKind.reply);
        expect(action?.eventId, isNull);
        expect(action?.replyText, 'hey');
      },
    );

    test('ignores a body tap (no actionId)', () {
      expect(
        messageNotificationActionFrom(
          actionId: null,
          payload: payloadWithEvent,
        ),
        isNull,
      );
    });

    test('ignores a call notification\'s payload sharing this dispatcher', () {
      expect(
        messageNotificationActionFrom(
          actionId: 'reply',
          payload:
              '{"roomId":"!room:example.org","callId":"c1",'
              '"callerId":"@alice:example.org","isVideo":true}',
        ),
        isNull,
      );
    });

    test('ignores an unknown actionId', () {
      expect(
        messageNotificationActionFrom(
          actionId: 'accept',
          payload: payloadWithEvent,
        ),
        isNull,
      );
    });

    test('ignores malformed or missing payloads instead of throwing', () {
      expect(
        messageNotificationActionFrom(actionId: 'mark_read', payload: null),
        isNull,
      );
      expect(
        messageNotificationActionFrom(
          actionId: 'mark_read',
          payload: 'not json',
        ),
        isNull,
      );
      expect(
        messageNotificationActionFrom(
          actionId: 'mark_read',
          payload: '[1,2,3]',
        ),
        isNull,
      );
    });

    test('ignores a payload missing roomId', () {
      expect(
        messageNotificationActionFrom(
          actionId: 'mark_read',
          payload: '{"type":"message"}',
        ),
        isNull,
      );
    });
  });

  group('runHeadlessMessageAction', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const wakeLock = MethodChannel('zuno/wake_lock');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> lockCalls;
    late List<String> requests;
    var failures = 0;

    setUp(() {
      lockCalls = [];
      requests = [];
      failures = 0;
      messenger.setMockMethodCallHandler(wakeLock, (call) async {
        lockCalls.add(call.method);
        return null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(wakeLock, null));

    Client clientWithRoom({bool knowsRoom = true, bool sendable = false}) {
      final client = buildTestClient(
        userId: '@me:example.org',
        deviceId: sendable ? null : 'DEV',
        database: sendable ? _SendCapableFakeDatabaseApi() : null,
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          lockCalls.add('request');
          if (failures > 0) {
            failures--;
            return http.Response('{"errcode":"M_UNKNOWN"}', 500);
          }
          if (request.url.path.contains('/send/')) {
            return http.Response('{"event_id":"\$sent"}', 200);
          }
          return http.Response('{}', 200);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      if (knowsRoom) client.rooms.add(buildTestRoom(client));
      return client;
    }

    const markRead = (
      kind: MessageNotificationActionKind.markRead,
      roomId: '!room:example.org',
      eventId: r'$1',
      replyText: null,
    );

    test('holds a wake lock across the whole action', () async {
      await runHeadlessMessageAction(
        markRead,
        clientBuilder: () async => clientWithRoom(),
        retryDelays: const [],
      );

      expect(lockCalls, ['acquire', 'request', 'release']);
      expect(requests.single, contains('read_markers'));
    });

    test('retries a failed request before giving up', () async {
      failures = 2;

      await runHeadlessMessageAction(
        markRead,
        clientBuilder: () async => clientWithRoom(),
        retryDelays: const [Duration.zero, Duration.zero],
      );

      expect(requests, hasLength(3));
      expect(lockCalls.last, 'release');
    });

    test(
      'gives up once the retries are spent, still releasing the lock',
      () async {
        failures = 10;

        await runHeadlessMessageAction(
          markRead,
          clientBuilder: () async => clientWithRoom(),
          retryDelays: const [Duration.zero],
        );

        expect(requests, hasLength(2));
        expect(lockCalls.last, 'release');
      },
    );

    test('a room this device does not know is skipped', () async {
      await runHeadlessMessageAction(
        markRead,
        clientBuilder: () async => clientWithRoom(knowsRoom: false),
        retryDelays: const [],
      );

      expect(requests, isEmpty);
      expect(lockCalls, ['acquire', 'release']);
    });

    test('a client that cannot be built still releases the lock', () async {
      await runHeadlessMessageAction(
        markRead,
        clientBuilder: () async => throw StateError('db locked'),
        retryDelays: const [],
      );

      expect(lockCalls, ['acquire', 'release']);
    });

    test('an action the running app takes over opens no client of its own, '
        'and the wake lock covers the hand-off', () async {
      final handed = <MessageNotificationAction>[];
      var builds = 0;

      await runHeadlessMessageAction(
        markRead,
        handOff: (action, _) async {
          handed.add(action);
          lockCalls.add('handOff');
          return true;
        },
        clientBuilder: () async {
          builds++;
          return clientWithRoom();
        },
        retryDelays: const [],
      );

      expect(handed, [markRead]);
      expect(builds, 0);
      expect(requests, isEmpty);
      expect(lockCalls, ['acquire', 'handOff', 'release']);
    });

    test('with no running app to take it, the action runs on a one-shot '
        'client, its wake lock taken afresh for the client', () async {
      await runHeadlessMessageAction(
        markRead,
        handOff: (_, _) async => false,
        clientBuilder: () async => clientWithRoom(),
        retryDelays: const [],
      );

      expect(lockCalls, ['acquire', 'acquire', 'request', 'release']);
      expect(requests.single, contains('read_markers'));
    });

    test('while the app holds the client, the action goes back to the app, '
        'more patiently', () async {
      var handOffs = 0;

      await runHeadlessMessageAction(
        markRead,
        handOff: (_, _) async {
          handOffs++;
          lockCalls.add('handOff');
          return handOffs == 3;
        },
        clientBuilder: () async => throw const ClientLeaseDenied(),
        retryDelays: const [],
        handOffRetryEvery: Duration.zero,
      );

      expect(handOffs, 3);
      expect(requests, isEmpty);
      expect(lockCalls, [
        'acquire',
        'handOff',
        'acquire',
        'acquire',
        'handOff',
        'handOff',
        'release',
      ]);
    });

    test('a patient hand-off gives up after about six seconds, and the '
        'action fails as before', () {
      fakeAsync((async) {
        var handOffs = 0;
        var done = false;

        runHeadlessMessageAction(
          markRead,
          handOff: (_, _) async {
            handOffs++;
            await Future<void>.delayed(const Duration(seconds: 2));
            return false;
          },
          clientBuilder: () async => throw const ClientLeaseDenied(),
          retryDelays: const [],
        ).then((_) => done = true);
        async.elapse(const Duration(seconds: 30));

        expect(done, isTrue);
        expect(handOffs, 4);
        expect(requests, isEmpty);
        expect(lockCalls.last, 'release');
      });
    });

    test(
      'with no route to the app, a refused client is a failed action',
      () async {
        await runHeadlessMessageAction(
          markRead,
          clientBuilder: () async => throw const ClientLeaseDenied(),
          retryDelays: const [],
        );

        expect(requests, isEmpty);
        expect(lockCalls, ['acquire', 'release']);
      },
    );

    test('each run holds its wake lock under its own tag, so two actions at '
        'once never release each other\'s lock', () async {
      final tagged = <String>[];
      messenger.setMockMethodCallHandler(wakeLock, (call) async {
        tagged.add('${call.method} ${(call.arguments as Map)['tag']}');
        return null;
      });
      final slow = Completer<Client>();

      final first = runHeadlessMessageAction(
        markRead,
        clientBuilder: () => slow.future,
        retryDelays: const [],
      );
      await runHeadlessMessageAction(
        markRead,
        clientBuilder: () async => clientWithRoom(),
        retryDelays: const [],
      );
      slow.complete(clientWithRoom());
      await first;

      Set<String> tags(String method) => {
        for (final step in tagged)
          if (step.startsWith('$method ')) step.substring(method.length + 1),
      };
      expect(tags('acquire'), hasLength(2));
      expect(tags('release'), tags('acquire'));
      expect(
        tags('acquire').every((tag) => tag.startsWith('message_action_')),
        isTrue,
      );
    });

    test('a hand-off that breaks falls back to the one-shot client', () async {
      await runHeadlessMessageAction(
        markRead,
        handOff: (_, _) async => throw StateError('no port'),
        clientBuilder: () async => clientWithRoom(),
        retryDelays: const [],
      );

      expect(requests.single, contains('read_markers'));
      expect(lockCalls.last, 'release');
    });

    test('a reply carries one transaction id to the app and keeps it when it '
        'has to send the reply itself, so a reply the app also sent is not '
        'posted twice', () async {
      const reply = (
        kind: MessageNotificationActionKind.reply,
        roomId: '!room:example.org',
        eventId: null,
        replyText: 'on my way',
      );
      String? handedTxid;

      await runHeadlessMessageAction(
        reply,
        handOff: (_, txid) async {
          handedTxid = txid;
          return false;
        },
        clientBuilder: () async => clientWithRoom(sendable: true),
        retryDelays: const [],
      );

      final sends = requests.where((r) => r.contains('/send/')).toList();
      expect(handedTxid, isNotNull);
      expect(sends.single, endsWith('/$handedTxid'));
    });

    test('a reply the server refuses is tried again under the same '
        'transaction id', () async {
      failures = 1;
      const reply = (
        kind: MessageNotificationActionKind.reply,
        roomId: '!room:example.org',
        eventId: null,
        replyText: 'on my way',
      );

      await runHeadlessMessageAction(
        reply,
        clientBuilder: () async => clientWithRoom(sendable: true),
        retryDelays: const [Duration.zero],
      );

      final sends = requests.where((r) => r.contains('/send/')).toList();
      expect(sends, hasLength(2));
      expect(sends.first, sends.last);
    });

    test('a reply performed without a given transaction id still keeps one '
        'across its retries', () async {
      failures = 1;
      final client = clientWithRoom(sendable: true);

      await performMessageNotificationAction(
        client.getRoomById('!room:example.org')!,
        (
          kind: MessageNotificationActionKind.reply,
          roomId: '!room:example.org',
          eventId: null,
          replyText: 'on my way',
        ),
        retryDelays: const [Duration.zero],
      );

      final sends = requests.where((r) => r.contains('/send/')).toList();
      expect(sends, hasLength(2));
      expect(sends.first, sends.last);
    });

    test('a wake lock names its own tag, so two kinds of action never '
        'release each other\'s lock', () async {
      final tags = <Object?>[];
      messenger.setMockMethodCallHandler(wakeLock, (call) async {
        tags.add((call.arguments as Map)['tag']);
        return null;
      });

      await const HeadlessWakeLock(tag: 'call_decline').acquire();
      await const HeadlessWakeLock().release();

      expect(tags, ['call_decline', 'message_action']);
    });

    test(
      'on a platform without wake locks the action runs with no lock',
      () async {
        await runHeadlessMessageAction(
          markRead,
          clientBuilder: () async => clientWithRoom(),
          wakeLock: HeadlessWakeLock(
            capabilities: capabilitiesLike(
              androidCapabilities,
              headlessWakeLocks: false,
            ),
          ),
          retryDelays: const [],
        );

        expect(lockCalls, ['request']);
        expect(requests.single, contains('read_markers'));
      },
    );
  });

  group('handing an action to the running app', () {
    test('a transaction id travels with the action', () {
      const markRead = (
        kind: MessageNotificationActionKind.markRead,
        roomId: '!room:example.org',
        eventId: r'$1',
        replyText: null,
      );

      expect(
        handedTxidOf(encodeMessageAction(markRead, txid: 'zuno-tx-2')),
        'zuno-tx-2',
      );
      expect(handedTxidOf(encodeMessageAction(markRead)), isNull);
    });

    test('an action survives the trip between isolates', () {
      const reply = (
        kind: MessageNotificationActionKind.reply,
        roomId: '!room:example.org',
        eventId: r'$1',
        replyText: 'on my way',
      );
      const markRead = (
        kind: MessageNotificationActionKind.markRead,
        roomId: '!room:example.org',
        eventId: null,
        replyText: null,
      );

      expect(decodeMessageAction(encodeMessageAction(reply)), reply);
      expect(decodeMessageAction(encodeMessageAction(markRead)), markRead);
    });

    test('anything else arriving on the route is refused', () {
      expect(decodeMessageAction(null), isNull);
      expect(decodeMessageAction('reply'), isNull);
      expect(decodeMessageAction({'kind': 'reply'}), isNull);
      expect(
        decodeMessageAction({'kind': 'forward', 'roomId': '!room:x'}),
        isNull,
      );
    });
  });

  group('replyToRoom', () {
    late List<Map<String, Object?>> sent;
    late List<String> sentPaths;
    var refuse = false;

    Room room() {
      final client = buildTestClient(
        userId: '@me:example.org',
        database: _SendCapableFakeDatabaseApi(),
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/send/')) {
            if (refuse) {
              return http.Response('{"errcode":"M_UNKNOWN"}', 500);
            }
            sent.add(jsonDecode(request.body) as Map<String, Object?>);
            sentPaths.add(request.url.path);
            return http.Response('{"event_id":"\$sent"}', 200);
          }
          return http.Response('{}', 200);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      final room = buildTestRoom(client);
      client.rooms.add(room);
      return room;
    }

    setUp(() {
      sent = [];
      sentPaths = [];
      refuse = false;
    });

    test('sends markdown characters as typed', () async {
      await replyToRoom(room(), '**bold** and _soft_');

      expect(sent.single['body'], '**bold** and _soft_');
      expect(sent.single.containsKey('formatted_body'), isFalse);
      expect(sent.single.containsKey('format'), isFalse);
    });

    test('a leading slash is text, not a command', () async {
      await replyToRoom(room(), '/shrug hi');

      expect(sent.single['body'], '/shrug hi');
      expect(sent.single['msgtype'], MessageTypes.Text);
    });

    test('a plain message goes out unchanged', () async {
      await replyToRoom(room(), 'on my way');

      expect(sent.single, {'msgtype': MessageTypes.Text, 'body': 'on my way'});
    });

    test('goes out under the transaction id it is given', () async {
      await replyToRoom(room(), 'on my way', txid: 'zuno-tx-7');

      expect(sentPaths.single, endsWith('/zuno-tx-7'));
    });

    test(
      'fails when the server refused it, so it can be tried again',
      () async {
        refuse = true;

        await expectLater(
          replyToRoom(room(), 'on my way'),
          throwsA(isA<NotificationReplyNotSent>()),
        );
      },
    );
  });
}
