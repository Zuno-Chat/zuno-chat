import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  final publishedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  final endsAt = publishedAt.add(const Duration(hours: 1));

  group('share state', () {
    test('round-trips through its content', () {
      final state = LiveShareState(
        shareId: 'share1',
        deviceId: 'PHONE',
        endsAt: endsAt,
      );

      final parsed = parseLiveShareState(
        state.toContent(),
        publishedAt: publishedAt,
      );

      expect(parsed, state);
      expect(state.toContent(), {
        'share_id': 'share1',
        'device_id': 'PHONE',
        'ends_ts': endsAt.millisecondsSinceEpoch,
      });
    });

    test('is open until its end and closed from then on', () {
      final state = LiveShareState(
        shareId: 'share1',
        deviceId: 'PHONE',
        endsAt: endsAt,
      );

      expect(state.isOpenAt(endsAt.subtract(const Duration(seconds: 1))), true);
      expect(state.isOpenAt(endsAt), false);
    });

    test('empty content means nobody is sharing', () {
      expect(parseLiveShareState({}, publishedAt: publishedAt), isNull);
      expect(parseLiveShareState(null, publishedAt: publishedAt), isNull);
    });

    test('rejects missing, empty or mistyped fields', () {
      for (final content in <Map<String, Object?>>[
        {'device_id': 'PHONE', 'ends_ts': endsAt.millisecondsSinceEpoch},
        {'share_id': '', 'device_id': 'PHONE', 'ends_ts': 1},
        {'share_id': 's', 'device_id': '', 'ends_ts': 1},
        {'share_id': 's', 'device_id': 'PHONE', 'ends_ts': '1'},
        {'share_id': 7, 'device_id': 'PHONE', 'ends_ts': 1},
        {'share_id': 's' * 256, 'device_id': 'PHONE', 'ends_ts': 1},
      ]) {
        expect(
          parseLiveShareState(content, publishedAt: publishedAt),
          isNull,
          reason: '$content',
        );
      }
    });

    test('rejects an end later than the longest share allows', () {
      Map<String, Object?> endingAt(DateTime end) => {
        'share_id': 'share1',
        'device_id': 'PHONE',
        'ends_ts': end.millisecondsSinceEpoch,
      };

      expect(
        parseLiveShareState(
          endingAt(publishedAt.add(const Duration(hours: 2, minutes: 10))),
          publishedAt: publishedAt,
        ),
        isNotNull,
      );
      expect(
        parseLiveShareState(
          endingAt(publishedAt.add(const Duration(hours: 2, minutes: 11))),
          publishedAt: publishedAt,
        ),
        isNull,
      );
    });

    group('in a room', () {
      late Room room;

      setUp(() {
        room = buildTestRoom(buildTestClient(userId: '@me:x'));
      });

      void setShareState(
        String stateKey,
        Map<String, Object?> content, {
        String? senderId,
      }) => room.setState(
        buildTestEvent(
          room,
          eventId: '\$state-$stateKey',
          senderId: senderId ?? stateKey,
          type: liveLocationStateType,
          stateKey: stateKey,
          originServerTs: publishedAt,
          content: content,
        ),
      );

      test('is read from the sharer\'s own state key', () {
        setShareState('@alex:x', {
          'share_id': 'share1',
          'device_id': 'PHONE',
          'ends_ts': endsAt.millisecondsSinceEpoch,
        });

        expect(
          liveShareStateOf(room, '@alex:x'),
          LiveShareState(shareId: 'share1', deviceId: 'PHONE', endsAt: endsAt),
        );
        expect(liveShareStateOf(room, '@bea:x'), isNull);
      });

      test('ignores a state written by someone else', () {
        setShareState('@alex:x', {
          'share_id': 'share1',
          'device_id': 'PHONE',
          'ends_ts': endsAt.millisecondsSinceEpoch,
        }, senderId: '@mallory:x');

        expect(liveShareStateOf(room, '@alex:x'), isNull);
      });

      test('a cleared state reads as no share', () {
        setShareState('@alex:x', {});

        expect(liveShareStateOf(room, '@alex:x'), isNull);
      });
    });
  });

  group('timestamps', () {
    test('read only integers that a date can hold', () {
      expect(liveTimestamp(1700000000000), isNotNull);
      for (final value in <Object?>[
        9000000000000000,
        -9000000000000000,
        9007199254740991,
        1700000000000.5,
        '1700000000000',
        null,
      ]) {
        expect(liveTimestamp(value), isNull, reason: '$value');
      }
    });

    test('a share, start or position past them reads as malformed', () {
      expect(
        parseLiveShareState({
          'share_id': 's',
          'device_id': 'PHONE',
          'ends_ts': 9000000000000000,
        }, publishedAt: publishedAt),
        isNull,
      );
      expect(
        parseLiveShareState({
          'ends_ts': -9000000000000000,
        }, publishedAt: publishedAt),
        isNull,
      );
      expect(
        parseLivePosition({
          'room_id': '!r:x',
          'share_id': 's',
          'geo_uri': 'geo:1,2',
          'ts': 9000000000000000,
        }),
        isNull,
      );
      final room = buildTestRoom(buildTestClient(userId: '@me:x'));
      expect(
        liveLocationStartOf(
          buildTestEvent(
            room,
            eventId: r'$huge',
            senderId: '@mallory:x',
            content: {
              'msgtype': liveLocationMsgtype,
              'share_id': 'x',
              'ends_ts': 9007199254740991,
            },
          ),
        ),
        isNull,
      );
    });
  });

  group('start message', () {
    late Room room;

    setUp(() {
      room = buildTestRoom(buildTestClient(userId: '@me:x'));
    });

    Event event(Map<String, Object?> content) => buildTestEvent(
      room,
      eventId: r'$start',
      senderId: '@alex:x',
      content: content,
    );

    test('names the duration in its fallback text and reads back', () {
      final content = liveLocationStartContent(
        shareId: 'share1',
        endsAt: endsAt,
        duration: LiveLocationDuration.hour,
      );

      expect(content['msgtype'], liveLocationMsgtype);
      expect(content['body'], 'Live location for 1 hour');
      expect(
        liveLocationStartOf(event(content)),
        LiveLocationStart(shareId: 'share1', endsAt: endsAt),
      );
    });

    test('labels every duration', () {
      expect(LiveLocationDuration.values.map((d) => d.label), [
        '15 minutes',
        '1 hour',
        '2 hours',
      ]);
      expect(LiveLocationDuration.values.map((d) => d.duration), const [
        Duration(minutes: 15),
        Duration(hours: 1),
        Duration(hours: 2),
      ]);
    });

    test('a pin or a malformed start is not a live start', () {
      expect(
        liveLocationStartOf(
          event({'msgtype': MessageTypes.Location, 'body': 'Location'}),
        ),
        isNull,
      );
      expect(
        liveLocationStartOf(
          event({'msgtype': liveLocationMsgtype, 'body': 'Live location'}),
        ),
        isNull,
      );
    });
  });

  group('position', () {
    const geo = GeoUri(
      latitude: 52.5163,
      longitude: 13.3777,
      uncertaintyMeters: 12,
    );
    final at = DateTime.fromMillisecondsSinceEpoch(1700000123000);

    test('round-trips through its content', () {
      final content = livePositionContent(
        roomId: '!r:x',
        shareId: 'share1',
        position: LivePosition(geo: geo, at: at),
      );

      expect(content, {
        'room_id': '!r:x',
        'share_id': 'share1',
        'geo_uri': 'geo:52.5163,13.3777;u=12',
        'ts': at.millisecondsSinceEpoch,
      });
      final parsed = parseLivePosition(content);
      expect(parsed?.roomId, '!r:x');
      expect(parsed?.shareId, 'share1');
      expect(parsed?.position, LivePosition(geo: geo, at: at));
    });

    test('rejects malformed content', () {
      final valid = livePositionContent(
        roomId: '!r:x',
        shareId: 'share1',
        position: LivePosition(geo: geo, at: at),
      );
      for (final broken in <Map<String, Object?>>[
        {...valid, 'geo_uri': 'not a uri'},
        {...valid, 'geo_uri': 'geo:91,0'},
        {...valid, 'room_id': null},
        {...valid, 'share_id': ''},
        {...valid, 'ts': '1700000123000'},
      ]) {
        expect(parseLivePosition(broken), isNull, reason: '$broken');
      }
    });
  });

  group('watch', () {
    test('round-trips through its content', () {
      final content = liveWatchContent(
        roomId: '!r:x',
        shareId: 'share1',
        active: true,
      );

      expect(content, {
        'room_id': '!r:x',
        'share_id': 'share1',
        'active': true,
      });
      final parsed = parseLiveWatch(content);
      expect(parsed?.roomId, '!r:x');
      expect(parsed?.shareId, 'share1');
      expect(parsed?.active, true);
    });

    test('rejects malformed content', () {
      expect(parseLiveWatch({'room_id': '!r:x', 'share_id': 'share1'}), isNull);
      expect(
        parseLiveWatch({'room_id': '!r:x', 'share_id': '', 'active': true}),
        isNull,
      );
      expect(parseLiveWatch({'share_id': 'share1', 'active': false}), isNull);
    });
  });

  test('share ids are 22 url-safe characters and do not repeat', () {
    final random = Random(1);
    final ids = {for (var i = 0; i < 50; i++) newLiveShareId(random)};

    expect(ids, hasLength(50));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    }
  });
}
