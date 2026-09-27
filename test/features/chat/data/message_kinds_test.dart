import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
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

  Event message(
    Map<String, Object?> content, {
    String type = EventTypes.Message,
    String? stateKey,
  }) => buildTestEvent(
    room,
    eventId: r'$e',
    senderId: '@bob:example.org',
    type: type,
    stateKey: stateKey,
    content: content,
  );

  group('classifyAttachment', () {
    final cases = <String, (Map<String, Object?>, String, AttachmentKind)>{
      'a photo': (
        {'msgtype': 'm.image', 'body': 'a.jpg'},
        EventTypes.Message,
        AttachmentKind.image,
      ),
      'a video': (
        {'msgtype': 'm.video', 'body': 'a.mp4'},
        EventTypes.Message,
        AttachmentKind.video,
      ),
      'a voice message': (
        {
          'msgtype': 'm.audio',
          'body': 'Voice message.ogg',
          'org.matrix.msc3245.voice': <String, Object?>{},
        },
        EventTypes.Message,
        AttachmentKind.voice,
      ),
      'a file': (
        {'msgtype': 'm.file', 'body': 'report.pdf'},
        EventTypes.Message,
        AttachmentKind.file,
      ),
      'a location': (
        {'msgtype': 'm.location', 'body': 'here', 'geo_uri': 'geo:1,2'},
        EventTypes.Message,
        AttachmentKind.location,
      ),
      'text': (
        {'msgtype': 'm.text', 'body': 'hi'},
        EventTypes.Message,
        AttachmentKind.none,
      ),
      'a call summary': (
        {
          'msgtype': callSummaryMsgtype,
          'body': 'Call',
          'call_id': 'c1',
          'kind': 'voice',
          'status': 'ended',
        },
        EventTypes.Message,
        AttachmentKind.none,
      ),
      'call signaling': (
        {'msgtype': callInviteMsgtype, 'body': 'Calling'},
        EventTypes.Message,
        AttachmentKind.none,
      ),
      'an undecryptable message': (
        {'algorithm': 'm.megolm.v1.aes-sha2'},
        EventTypes.Encrypted,
        AttachmentKind.none,
      ),
      'a state event': (
        {'name': 'Room'},
        EventTypes.RoomName,
        AttachmentKind.none,
      ),
    };
    cases.forEach((label, value) {
      final (content, type, expected) = value;
      test('$label is ${expected.name}', () {
        final stateKey = type == EventTypes.RoomName ? '' : null;
        expect(
          classifyAttachment(message(content, type: type, stateKey: stateKey)),
          expected,
        );
      });
    });

    test('a deleted message is no attachment', () {
      final event = message({})
        ..unsigned = {
          'redacted_because': {
            'event_id': r'$r',
            'type': 'm.room.redaction',
            'sender': '@bob:example.org',
            'origin_server_ts': 0,
            'content': <String, Object?>{},
          },
        };
      expect(classifyAttachment(event), AttachmentKind.none);
    });
  });

  group('attachmentInfoText', () {
    test('a photo gives its size in pixels and bytes', () {
      final event = message({
        'msgtype': 'm.image',
        'body': 'a.jpg',
        'info': {'w': 1600, 'h': 1200, 'size': 2048},
      });
      expect(
        attachmentInfoText(event, AttachmentKind.image),
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
        attachmentInfoText(event, AttachmentKind.video),
        '640 × 360 · 01:23 · 3.0 MB',
      );
    });

    test('a file gives only its size, even with dimensions', () {
      final event = message({
        'msgtype': 'm.file',
        'body': 'a.pdf',
        'info': {'w': 10, 'h': 10, 'size': 512},
      });
      expect(attachmentInfoText(event, AttachmentKind.file), '512 B');
    });

    test('half a size is left out', () {
      final event = message({
        'msgtype': 'm.image',
        'body': 'a.jpg',
        'info': {'w': 10},
      });
      expect(
        attachmentInfoText(event, AttachmentKind.image),
        'No file information available',
      );
    });
  });

  group('displayBody and previewSnippet', () {
    test('a reply drops the quoted fallback', () async {
      final event = message({
        'msgtype': 'm.text',
        'body': '> <@alice:example.org> earlier\n\nnow',
      });
      final timeline = await timelineOf([event]);

      expect(displayBody(event, timeline), 'now');
      expect(previewSnippet(event, timeline), 'now');
    });

    test('an attachment previews by kind, not file name', () async {
      final event = message({'msgtype': 'm.image', 'body': 'IMG_1.jpg'});
      final timeline = await timelineOf([event]);

      expect(previewSnippet(event, timeline), 'Photo');
    });
  });

  test('state events and edits are hidden from the timeline', () {
    expect(
      isHiddenTimelineEvent(
        message({'name': 'R'}, type: EventTypes.RoomName, stateKey: ''),
      ),
      isTrue,
    );
    expect(
      isHiddenTimelineEvent(
        message({
          'msgtype': 'm.text',
          'body': '* fixed',
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$o'},
        }),
      ),
      isTrue,
    );
    expect(isHiddenTimelineEvent(message({'msgtype': 'm.text'})), isFalse);
  });

  group('formatDuration', () {
    test('pads minutes and seconds', () {
      expect(formatDuration(const Duration(seconds: 7)), '00:07');
      expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12:05');
    });

    test('keeps the hours of a long call or video', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 5, seconds: 3)),
        '1:05:03',
      );
      expect(formatDuration(const Duration(hours: 12)), '12:00:00');
    });
  });
}
