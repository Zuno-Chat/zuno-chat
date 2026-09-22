import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
  });

  Event media(
    String eventId, {
    String msgtype = MessageTypes.Image,
    String? groupId,
    int index = 0,
    int count = 2,
  }) => buildTestEvent(
    room,
    eventId: eventId,
    senderId: '@me:example.org',
    content: {
      'msgtype': msgtype,
      'body': eventId,
      if (groupId != null)
        ...galleryGroupContent(id: groupId, index: index, count: count),
    },
  );

  group('galleryGroupOf', () {
    test('round-trips what galleryGroupContent wrote', () {
      final ref = galleryGroupOf(media('a', groupId: 'g1', index: 1, count: 3));
      expect(ref, isNotNull);
      expect(ref!.id, 'g1');
      expect(ref.index, 1);
      expect(ref.count, 3);
    });

    test('is null for a plain media message', () {
      expect(galleryGroupOf(media('a')), isNull);
    });

    test('is null for a malformed group key rather than throwing', () {
      final event = buildTestEvent(
        room,
        eventId: 'a',
        senderId: '@me:example.org',
        content: {
          'msgtype': MessageTypes.Image,
          'body': 'a',
          galleryGroupKey: {'id': 'g1', 'index': 'first', 'count': 2},
        },
      );
      expect(galleryGroupOf(event), isNull);
    });

    test('is null for an out-of-range index or a count below two', () {
      expect(
        galleryGroupOf(media('a', groupId: 'g1', index: 5, count: 3)),
        isNull,
      );
      expect(
        galleryGroupOf(media('b', groupId: 'g1', index: 0, count: 1)),
        isNull,
      );
    });
  });

  group('groupGalleries', () {
    test('folds a multi-file send into one anchored tile', () {
      final newest = media('b', groupId: 'g1', index: 1);
      final oldest = media('a', groupId: 'g1', index: 0);
      final result = groupGalleries([newest, oldest]);

      expect(result.messages.map((e) => e.eventId), ['b']);
      expect(result.galleries.keys, ['b']);
      expect(result.galleries['b']!.map((e) => e.eventId), ['a', 'b']);
    });

    test('leaves a single media message standalone', () {
      final result = groupGalleries([media('b'), media('a')]);
      expect(result.galleries, isEmpty);
      expect(result.messages.map((e) => e.eventId), ['b', 'a']);
    });

    test('does not group a lone survivor of a redacted pair', () {
      final redacted = media('b', groupId: 'g1', index: 1);
      redacted.setRedactionEvent(
        buildTestEvent(
          room,
          eventId: 'r',
          senderId: '@me:example.org',
          type: EventTypes.Redaction,
        ),
      );
      final result = groupGalleries([redacted, media('a', groupId: 'g1')]);

      expect(result.galleries, isEmpty);
      expect(result.messages.map((e) => e.eventId), ['b', 'a']);
    });

    test('keeps a one-item group when its other item failed to send', () {
      final result = groupGalleries([
        media('a', groupId: 'g1', index: 0),
      ], forceGroupIds: {'g1'});

      expect(result.galleries.keys, ['a']);
      expect(result.galleries['a']!.map((e) => e.eventId), ['a']);
    });

    test('keeps unrelated messages between two galleries in place', () {
      final result = groupGalleries([
        media('d', groupId: 'g2', index: 1),
        media('c', groupId: 'g2', index: 0),
        buildTestEvent(
          room,
          eventId: 'text',
          senderId: '@you:example.org',
          content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
        ),
        media('b', groupId: 'g1', index: 1),
        media('a', groupId: 'g1', index: 0),
      ]);

      expect(result.messages.map((e) => e.eventId), ['d', 'text', 'b']);
      expect(result.galleries['d']!.map((e) => e.eventId), ['c', 'd']);
      expect(result.galleries['b']!.map((e) => e.eventId), ['a', 'b']);
    });

    test('groups mixed photos and videos sent together', () {
      final result = groupGalleries([
        media('v', msgtype: MessageTypes.Video, groupId: 'g1', index: 1),
        media('i', groupId: 'g1', index: 0),
      ]);
      expect(result.galleries['v']!.map((e) => e.eventId), ['i', 'v']);
    });
  });

  group('galleryTileLayout', () {
    test('shows every thumbnail up to four', () {
      expect(galleryTileLayout(2).visible, 2);
      expect(galleryTileLayout(2).overflow, 0);
      expect(galleryTileLayout(4).visible, 4);
      expect(galleryTileLayout(4).overflow, 0);
    });

    test('collapses the rest into a "+N" on the fourth', () {
      expect(galleryTileLayout(7).visible, 4);
      expect(galleryTileLayout(7).overflow, 3);
    });
  });
}
