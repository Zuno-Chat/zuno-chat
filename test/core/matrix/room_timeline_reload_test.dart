import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_timeline_reload.dart';
import 'package:zuno/core/matrix/sync_coordinator.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

class _RoomStore extends StoredEventsFakeDatabaseApi with SendCapableDatabase {
  final storedPrevBatches = <String?>[];
  var deletes = 0;
  bool Function() idle = () => true;
  final idleAtDelete = <bool>[];

  @override
  Future<void> deleteTimelineForRoom(String roomId) async {
    idleAtDelete.add(idle());
    deletes++;
    events = [];
  }

  @override
  Future<void> setRoomPrevBatch(
    String? prevBatch,
    String roomId,
    Client client,
  ) async => storedPrevBatches.add(prevBatch);

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {
    if (event is! MatrixEvent) return;
    final room = client.getRoomById(roomId)!;
    final stored = Event.fromMatrixEvent(event, room);
    events = type == EventUpdateType.history
        ? [...events, stored]
        : [stored, ...events];
  }
}

class _HeldSync implements SyncCoordinator {
  var held = false;

  @override
  Future<void> whileIdle(Future<void> Function() action) async {
    held = true;
    try {
      await action();
    } finally {
      held = false;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _message(String id) => {
  'event_id': id,
  'type': EventTypes.Message,
  'sender': '@bob:example.org',
  'origin_server_ts': 1760000000000,
  'content': {'msgtype': 'm.text', 'body': id},
};

void main() {
  late _RoomStore db;
  late Room room;
  late List<http.Request> messageRequests;
  late http.Response Function() latestPage;

  setUp(() {
    db = _RoomStore();
    messageRequests = [];
    latestPage = () => http.Response(
      jsonEncode({
        'start': 't_now',
        'end': 't_before_new1',
        'chunk': [_message(r'$new2'), _message(r'$new1')],
      }),
      200,
    );
    final client = buildTestClient(
      userId: '@me:example.org',
      database: db,
      httpClient: FakeHttpClient((request) async {
        if (!request.url.path.endsWith('/messages')) {
          return http.Response('{}', 200);
        }
        messageRequests.add(request);
        expect(db.idle(), isTrue, reason: 'a sync could land mid-reload');
        return messageRequests.length == 1
            ? latestPage()
            : http.Response(jsonEncode({'start': 'x', 'chunk': []}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'token';
    room = buildTestRoom(client)
      ..partial = false
      ..prev_batch = 't_stale';
    client.rooms.add(room);
    db.events = [
      buildTestEvent(
        room,
        eventId: r'$stale',
        senderId: '@bob:example.org',
        status: EventStatus.synced,
      ),
    ];
  });

  Future<List<String>> timelineIds() async {
    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    return [for (final event in timeline.events) event.eventId];
  }

  test('rebuilds the room from its latest messages', () async {
    await reloadRoomTimeline(room, sync: null);

    final request = messageRequests.single.url.queryParameters;
    expect(request['dir'], 'b');
    expect(request.containsKey('from'), isFalse);
    expect(await timelineIds(), [r'$new2', r'$new1']);
  });

  test('scrolling up afterwards continues from before the latest messages, '
      'not from where the old history stopped', () async {
    await reloadRoomTimeline(room, sync: null);

    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    await timeline.requestHistory();

    expect(messageRequests.last.url.queryParameters['from'], 't_before_new1');
    expect(db.storedPrevBatches.first, 't_before_new1');
  });

  test(
    'a room whose whole history fits in one page has no more to load',
    () async {
      latestPage = () => http.Response(
        jsonEncode({
          'start': 't_now',
          'chunk': [_message(r'$only')],
        }),
        200,
      );

      await reloadRoomTimeline(room, sync: null);

      expect(room.prev_batch, isNull);
      expect(db.storedPrevBatches, [null]);
      expect(await timelineIds(), [r'$only']);
    },
  );

  test('a failed download keeps what is there', () async {
    latestPage = () => http.Response('{"errcode":"M_UNKNOWN"}', 502);

    await expectLater(reloadRoomTimeline(room, sync: null), throwsA(anything));

    expect(db.deletes, 0);
    expect(room.prev_batch, 't_stale');
    expect(await timelineIds(), [r'$stale']);
  });

  test('a room you are no longer in stays out of the chat list', () async {
    room.client.rooms.remove(room);
    room.membership = Membership.leave;

    await expectLater(
      reloadRoomTimeline(room, sync: null),
      throwsA(isA<StateError>()),
    );

    expect(canReloadRoomTimeline(room), isFalse);
    expect(messageRequests, isEmpty);
    expect(db.deletes, 0);
    expect(room.client.rooms, isEmpty);
  });

  test('runs while sync is idle, so no sync lands between the download and '
      'the swap', () async {
    final sync = _HeldSync();
    db.idle = () => sync.held;

    await reloadRoomTimeline(room, sync: sync);

    expect(messageRequests, hasLength(1));
    expect(db.idleAtDelete, [true]);
    expect(sync.held, isFalse);
  });
}
