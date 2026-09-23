import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/notifications/message_notification_action.dart';

import '../../helpers/fake_matrix.dart';

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

    Client clientWithRoom({bool knowsRoom = true}) {
      final client = buildTestClient(
        userId: '@me:example.org',
        deviceId: 'DEV',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          lockCalls.add('request');
          if (failures > 0) {
            failures--;
            return http.Response('{"errcode":"M_UNKNOWN"}', 500);
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
  });

  group('replyToRoom', () {
    late List<Map<String, Object?>> sent;

    Room room() {
      final client = buildTestClient(
        userId: '@me:example.org',
        database: _SendCapableFakeDatabaseApi(),
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/send/')) {
            sent.add(jsonDecode(request.body) as Map<String, Object?>);
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

    setUp(() => sent = []);

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
  });
}
