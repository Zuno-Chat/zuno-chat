import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_media_feed.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  Event message(
    String id,
    Map<String, Object?> content, {
    int ts = 0,
    String type = EventTypes.Message,
    EventStatus? status,
    Room? inRoom,
  }) => buildTestEvent(
    inRoom ?? room,
    eventId: id,
    senderId: '@a:example.org',
    type: type,
    content: content,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    status: status,
  );

  Event image(String id, {int ts = 0, Room? inRoom}) => message(
    id,
    {'msgtype': 'm.image', 'body': 'a.jpg', 'url': 'mxc://x/$id'},
    ts: ts,
    inRoom: inRoom,
  );

  Event video(String id, {int ts = 0}) => message(id, {
    'msgtype': 'm.video',
    'body': 'a.mp4',
    'url': 'mxc://x/$id',
  }, ts: ts);

  Event file(String id, {int ts = 0}) => message(id, {
    'msgtype': 'm.file',
    'body': 'a.pdf',
    'url': 'mxc://x/$id',
  }, ts: ts);

  Event text(String id) => message(id, {'msgtype': 'm.text', 'body': 'hi'});

  group('roomMediaKindOf', () {
    test('photo for images and stickers', () {
      expect(roomMediaKindOf(image(r'$i')), RoomMediaKind.photo);
      expect(
        roomMediaKindOf(
          message(r'$s', {
            'body': 'sticker',
            'url': 'mxc://x/s',
          }, type: EventTypes.Sticker),
        ),
        RoomMediaKind.photo,
      );
    });

    test('video', () {
      expect(roomMediaKindOf(video(r'$v')), RoomMediaKind.video);
    });

    test('file for files and plain audio', () {
      expect(roomMediaKindOf(file(r'$f')), RoomMediaKind.file);
      expect(
        roomMediaKindOf(
          message(r'$a', {
            'msgtype': 'm.audio',
            'body': 'song.mp3',
            'url': 'mxc://x/a',
          }),
        ),
        RoomMediaKind.file,
      );
    });

    test('null for text, voice and location', () {
      expect(roomMediaKindOf(text(r'$t')), isNull);
      expect(
        roomMediaKindOf(
          message(r'$voice', {
            'msgtype': 'm.audio',
            'body': 'voice',
            'url': 'mxc://x/voice',
            'org.matrix.msc3245.voice': <String, Object?>{},
          }),
        ),
        isNull,
      );
      expect(
        roomMediaKindOf(
          message(r'$loc', {
            'msgtype': 'm.location',
            'body': 'here',
            'geo_uri': 'geo:1,2',
          }),
        ),
        isNull,
      );
    });

    test('null for redacted, edits and unsent media', () {
      final redacted = Event(
        eventId: r'$gone',
        type: EventTypes.Message,
        senderId: '@a:example.org',
        originServerTs: DateTime.now(),
        content: {},
        room: room,
        unsigned: {
          'redacted_because': {
            'event_id': r'$r',
            'sender': '@a:example.org',
            'type': EventTypes.Redaction,
            'origin_server_ts': 0,
            'content': <String, Object?>{},
            'redacts': r'$gone',
          },
        },
      );
      expect(roomMediaKindOf(redacted), isNull);

      final edit = message(r'$edit', {
        'msgtype': 'm.image',
        'body': '* a.jpg',
        'url': 'mxc://x/e',
        'm.new_content': {
          'msgtype': 'm.image',
          'body': 'a.jpg',
          'url': 'mxc://x/e',
        },
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$orig'},
      });
      expect(roomMediaKindOf(edit), isNull);

      final unsent = message(r'$sending', {
        'msgtype': 'm.image',
        'body': 'a.jpg',
        'url': 'mxc://x/u',
      }, status: EventStatus.sending);
      expect(roomMediaKindOf(unsent), isNull);
    });
  });

  group('loadMore', () {
    RoomMediaFeed feedOver(
      Map<String?, RoomMediaBatch> pages, {
      int pageSize = 40,
      int maxRequestsPerLoad = 4,
      List<String?>? calls,
    }) => RoomMediaFeed(
      room,
      pageSize: pageSize,
      maxRequestsPerLoad: maxRequestsPerLoad,
      fetchPage: (cursor) async {
        calls?.add(cursor);
        return pages[cursor]!;
      },
    );

    test(
      'walks history until the end, newest first, skipping non-media',
      () async {
        final calls = <String?>[];
        final feed = feedOver({
          null: (
            events: [image(r'$1', ts: 3), text(r'$t'), video(r'$2', ts: 2)],
            nextBatch: 'b1',
          ),
          'b1': (events: [file(r'$3', ts: 1)], nextBatch: null),
        }, calls: calls);
        addTearDown(feed.dispose);

        await feed.loadMore();

        expect(feed.items.map((e) => e.eventId), [r'$1', r'$2', r'$3']);
        expect(feed.visuals.map((e) => e.eventId), [r'$1', r'$2']);
        expect(feed.files.map((e) => e.eventId), [r'$3']);
        expect(feed.hasMore, isFalse);
        expect(feed.stalled, isFalse);
        expect(calls, [null, 'b1']);
      },
    );

    test('stops once a page is full and resumes from the cursor', () async {
      final calls = <String?>[];
      final feed = feedOver(
        {
          null: (events: [image(r'$1'), image(r'$2')], nextBatch: 'b1'),
          'b1': (events: [image(r'$3')], nextBatch: null),
        },
        pageSize: 2,
        calls: calls,
      );
      addTearDown(feed.dispose);

      await feed.loadMore();
      expect(feed.items.length, 2);
      expect(feed.hasMore, isTrue);
      expect(calls, [null]);

      await feed.loadMore();
      expect(feed.items.length, 3);
      expect(feed.hasMore, isFalse);
      expect(calls, [null, 'b1']);

      await feed.loadMore();
      expect(calls, [null, 'b1']);
    });

    test('ignores duplicates across pages', () async {
      final feed = feedOver({
        null: (events: [image(r'$1'), image(r'$2')], nextBatch: 'b1'),
        'b1': (events: [image(r'$2'), image(r'$3')], nextBatch: null),
      });
      addTearDown(feed.dispose);

      await feed.loadMore();

      expect(feed.items.map((e) => e.eventId), [r'$1', r'$2', r'$3']);
    });

    test('caps requests per load and reports an empty load', () async {
      final calls = <String?>[];
      final feed = feedOver(
        {
          null: (events: [text(r'$a')], nextBatch: 'b1'),
          'b1': (events: [text(r'$b')], nextBatch: 'b2'),
          'b2': (events: [image(r'$c')], nextBatch: null),
        },
        maxRequestsPerLoad: 2,
        calls: calls,
      );
      addTearDown(feed.dispose);

      await feed.loadMore();

      expect(calls, [null, 'b1']);
      expect(feed.items, isEmpty);
      expect(feed.hasMore, isTrue);
      expect(feed.stalled, isTrue);

      await feed.loadMore();
      expect(feed.items.length, 1);
      expect(feed.hasMore, isFalse);
      expect(feed.stalled, isFalse);
    });

    test('coalesces concurrent calls and notifies around the load', () async {
      final calls = <String?>[];
      final feed = feedOver({
        null: (events: [image(r'$1')], nextBatch: null),
      }, calls: calls);
      addTearDown(feed.dispose);
      var notified = 0;
      feed.addListener(() => notified++);

      final first = feed.loadMore();
      expect(feed.loading, isTrue);
      await Future.wait([first, feed.loadMore()]);

      expect(calls, [null]);
      expect(feed.loading, isFalse);
      expect(notified, 2);
    });

    test('ensureLoaded loads once', () async {
      final calls = <String?>[];
      final feed = feedOver(
        {
          null: (events: [image(r'$1')], nextBatch: 'b1'),
          'b1': (events: [image(r'$2')], nextBatch: null),
        },
        pageSize: 1,
        calls: calls,
      );
      addTearDown(feed.dispose);

      await feed.ensureLoaded();
      await feed.ensureLoaded();

      expect(calls, [null]);
    });

    test('marks a failed load stalled and stays retryable', () async {
      var attempts = 0;
      final feed = RoomMediaFeed(
        room,
        fetchPage: (cursor) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          return (events: [image(r'$1')], nextBatch: null);
        },
      );
      addTearDown(feed.dispose);

      await expectLater(feed.loadMore(), throwsStateError);
      expect(feed.loading, isFalse);
      expect(feed.hasMore, isTrue);
      expect(feed.stalled, isTrue);
      expect(feed.failed, isTrue);

      await feed.loadMore();
      expect(feed.items.length, 1);
      expect(feed.failed, isFalse);
    });
  });

  group('live updates', () {
    late RoomMediaFeed feed;

    setUp(() async {
      feed = RoomMediaFeed(
        room,
        fetchPage: (_) async => (events: [image(r'$old')], nextBatch: null),
      );
      addTearDown(feed.dispose);
      await feed.loadMore();
    });

    test('prepends new media from sync for this room only', () async {
      final other = buildTestRoom(client, id: '!other:example.org');
      client.onTimelineEvent.add(image(r'$elsewhere', inRoom: other));
      client.onTimelineEvent.add(text(r'$chat'));
      client.onTimelineEvent.add(image(r'$new'));
      await pumpEventQueue();

      expect(feed.items.map((e) => e.eventId), [r'$new', r'$old']);
    });

    test('drops a redacted item', () async {
      client.onTimelineEvent.add(
        Event(
          eventId: r'$r',
          type: EventTypes.Redaction,
          senderId: '@a:example.org',
          originServerTs: DateTime.now(),
          content: {'redacts': r'$old'},
          room: room,
        ),
      );
      await pumpEventQueue();

      expect(feed.items, isEmpty);
    });

    test('ignores a duplicate of a loaded item', () async {
      client.onTimelineEvent.add(image(r'$old'));
      await pumpEventQueue();

      expect(feed.items.length, 1);
    });
  });

  group('roomMediaFeedProvider', () {
    test('keeps one feed per room and replaces it after logout', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(roomMediaFeedProvider(room));
      expect(container.read(roomMediaFeedProvider(room)), same(first));
      expect(
        container.read(
          roomMediaFeedProvider(
            buildTestRoom(client, id: '!other:example.org'),
          ),
        ),
        isNot(same(first)),
      );

      client.onLoginStateChanged.add(LoginState.loggedOut);
      await pumpEventQueue();

      expect(container.read(roomMediaFeedProvider(room)), isNot(same(first)));
    });
  });
}
