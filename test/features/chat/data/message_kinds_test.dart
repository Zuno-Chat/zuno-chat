import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/event_display.dart';
import 'package:zuno/features/chat/data/message_kinds.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late StoredEventsFakeDatabaseApi db;
  late Client client;
  late Room room;

  setUp(() {
    db = StoredEventsFakeDatabaseApi();
    client = buildTestClient(userId: '@me:example.org', database: db);
    room = buildTestRoom(client)..partial = false;
    room.setState(User('@bob:example.org', membership: 'join', room: room));
  });

  Future<Timeline> timelineOf(List<Event> events) async {
    db.events = events;
    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    return timeline;
  }

  Event message(Map<String, Object?> content) => buildTestEvent(
    room,
    eventId: r'$e',
    senderId: '@bob:example.org',
    content: content,
  );

  group('attachmentInfoText', () {
    test('a photo gives its size in pixels and bytes', () {
      final event = message({
        'msgtype': 'm.image',
        'body': 'a.jpg',
        'info': {'w': 1600, 'h': 1200, 'size': 2048},
      });
      expect(
        attachmentInfoText(englishLocalizations, event, MessageKind.photo),
        '1600 × 1200 · 2.0 KB',
      );
    });

    test('a video adds its length', () {
      final event = message({
        'msgtype': 'm.video',
        'body': 'a.mp4',
        'info': {'w': 640, 'h': 360, 'duration': 83000, 'size': 3 << 20},
      });
      expect(
        attachmentInfoText(englishLocalizations, event, MessageKind.video),
        '640 × 360 · 1:23 · 3.0 MB',
      );
    });

    test('a file gives only its size, even with dimensions', () {
      final event = message({
        'msgtype': 'm.file',
        'body': 'a.pdf',
        'info': {'w': 10, 'h': 10, 'size': 512},
      });
      expect(
        attachmentInfoText(englishLocalizations, event, MessageKind.file),
        '512 B',
      );
    });

    test('a size of nothing is left out', () {
      final event = message({
        'msgtype': 'm.video',
        'body': 'a.mp4',
        'info': {'w': 0, 'h': 0, 'size': 512},
      });
      expect(
        attachmentInfoText(englishLocalizations, event, MessageKind.video),
        '512 B',
      );
    });

    test('half a size is left out', () {
      final event = message({
        'msgtype': 'm.image',
        'body': 'a.jpg',
        'info': {'w': 10},
      });
      expect(
        attachmentInfoText(englishLocalizations, event, MessageKind.photo),
        'No file information available',
      );
    });
  });

  test(
    'displayBody and previewSnippet drop the quoted reply fallback',
    () async {
      final event = message({
        'msgtype': 'm.text',
        'body': '> <@alice:example.org> earlier\n\nnow',
      });
      final timeline = await timelineOf([event]);

      expect(displayBody(event, timeline), 'now');
      expect(previewSnippet(englishLocalizations, event, timeline), 'now');
    },
  );
}
