import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/matrix/event_display.dart';

import '../../helpers/fake_matrix.dart';

class _Case {
  final String name;

  final Event Function(Room room) build;

  final bool visible;

  final bool visibleWhenShowingHidden;

  final bool? previewable;

  final MessageKind kind;

  final String? text;

  const _Case(
    this.name, {
    required this.build,
    required this.visible,
    required this.visibleWhenShowingHidden,
    required this.kind,
    this.previewable,
    this.text,
  });
}

Event _msg(Room room, Map<String, Object?> content) =>
    buildTestEvent(room, eventId: r'$e', senderId: '@a:x', content: content);

final _cases = <_Case>[
  _Case(
    'plain text',
    build: (room) =>
        _msg(room, {'msgtype': MessageTypes.Text, 'body': 'hello there'}),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.text,
    text: 'hello there',
  ),
  _Case(
    'formatted message with an empty plain body',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Text,
      'body': '',
      'format': 'org.matrix.custom.html',
      'formatted_body': '<b>bold</b> words',
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.text,
    text: '**bold** words',
  ),
  _Case(
    'reply, whose raw body carries the quoted fallback',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Text,
      'body': '> <@b:x> original\n\nmy answer',
      'm.relates_to': {
        'm.in_reply_to': {'event_id': r'$orig'},
      },
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.text,
    text: 'my answer',
  ),
  _Case(
    'edit of an earlier message',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Text,
      'body': '* fixed text',
      'm.new_content': {'msgtype': MessageTypes.Text, 'body': 'fixed text'},
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': r'$orig',
      },
    }),
    visible: false,
    visibleWhenShowingHidden: false,
    previewable: true,
    kind: MessageKind.text,
    text: 'fixed text',
  ),
  _Case(
    'edit carrying no replacement content',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Text,
      'body': '* fixed text',
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': r'$orig',
      },
    }),
    visible: false,
    visibleWhenShowingHidden: false,
    kind: MessageKind.text,
    text: '* fixed text',
  ),
  _Case(
    'edit of a hidden signaling message',
    build: (room) => _msg(room, {
      'msgtype': callInviteMsgtype,
      'body': '* Incoming voice call',
      'm.new_content': {
        'msgtype': callInviteMsgtype,
        'body': 'Incoming voice call',
      },
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': r'$orig',
      },
    }),
    visible: false,
    visibleWhenShowingHidden: false,
    kind: MessageKind.hiddenSignaling,
  ),
  _Case(
    'redacted message',
    build: (room) => _msg(room, {'msgtype': MessageTypes.Text, 'body': 'hello'})
      ..setRedactionEvent(
        buildTestEvent(room, eventId: r'$r', senderId: '@a:x'),
      ),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.deleted,
    text: 'Message deleted',
  ),
  _Case(
    'undecryptable event',
    build: (room) => buildTestEvent(
      room,
      eventId: r'$e',
      senderId: '@a:x',
      type: EventTypes.Encrypted,
    ),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.undecryptable,
    text: 'Message cannot be read on this device',
  ),
  _Case(
    'image with a caption',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Image,
      'body': 'look at this',
      'filename': 'photo.jpg',
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.photo,
    text: 'look at this',
  ),
  _Case(
    'image with no caption (body == filename)',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Image,
      'body': 'photo.jpg',
      'filename': 'photo.jpg',
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.photo,
    text: 'Photo',
  ),
  _Case(
    'sticker',
    build: (room) => buildTestEvent(
      room,
      eventId: r'$e',
      senderId: '@a:x',
      type: EventTypes.Sticker,
      content: {'body': 'sticker.png', 'filename': 'sticker.png'},
    ),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.photo,
    text: 'Photo',
  ),
  _Case(
    'video',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Video,
      'body': 'clip.mp4',
      'filename': 'clip.mp4',
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.video,
    text: 'Video',
  ),
  _Case(
    'voice message',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Audio,
      'body': 'voice.ogg',
      'org.matrix.msc3245.voice': <String, Object?>{},
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.voice,
    text: 'Voice message',
  ),
  _Case(
    'plain audio attachment',
    build: (room) =>
        _msg(room, {'msgtype': MessageTypes.Audio, 'body': 'song.mp3'}),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.file,
    text: 'song.mp3',
  ),
  _Case(
    'file attachment',
    build: (room) =>
        _msg(room, {'msgtype': MessageTypes.File, 'body': 'notes.pdf'}),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.file,
    text: 'notes.pdf',
  ),
  _Case(
    'location pin',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Location,
      'body': 'Location: 52.5163, 13.3777',
      'geo_uri': 'geo:52.5163,13.3777;u=25',
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.location,
    text: 'Location',
  ),
  _Case(
    'location pin with a malformed geo_uri',
    build: (room) => _msg(room, {
      'msgtype': MessageTypes.Location,
      'body': 'User Location',
      'geo_uri': 'geo:nowhere',
    }),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.location,
    text: 'Location',
  ),
  _Case(
    'missed call summary',
    build: (room) => _msg(
      room,
      const CallSummary(
        callId: 'c1',
        kind: 'voice',
        status: CallSummaryStatus.missed,
        durationMs: 0,
      ).toMessageContent(),
    ),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.callSummary,
    text: 'Missed Voice call',
  ),
  _Case(
    'answered call summary',
    build: (room) => _msg(
      room,
      const CallSummary(
        callId: 'c1',
        kind: 'video',
        status: CallSummaryStatus.ended,
        durationMs: 332000,
      ).toMessageContent(),
    ),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.callSummary,
    text: 'Video call · 5:32',
  ),
  _Case(
    'declined call summary',
    build: (room) => _msg(
      room,
      const CallSummary(
        callId: 'c1',
        kind: 'voice',
        status: CallSummaryStatus.declined,
        durationMs: 0,
      ).toMessageContent(),
    ),
    visible: true,
    visibleWhenShowingHidden: true,
    kind: MessageKind.callSummary,
    text: 'Voice call declined',
  ),
  _Case(
    'call ring signaling',
    build: (room) => _msg(room, {
      'msgtype': callInviteMsgtype,
      'body': 'Incoming video call',
      'call_id': 'c1',
      'kind': 'video',
    }),
    visible: false,
    visibleWhenShowingHidden: true,
    kind: MessageKind.hiddenSignaling,
  ),
  _Case(
    'call decline signaling',
    build: (room) =>
        _msg(room, {'msgtype': callDeclineMsgtype, 'body': 'Call declined'}),
    visible: false,
    visibleWhenShowingHidden: true,
    kind: MessageKind.hiddenSignaling,
  ),
  _Case(
    'in-room verification request',
    build: (room) => _msg(room, {
      'msgtype': 'm.key.verification.request',
      'body':
          "Attempting verification request. Apparently your client "
          "doesn't support this",
    }),
    visible: false,
    visibleWhenShowingHidden: false,
    kind: MessageKind.hiddenSignaling,
  ),
  _Case(
    'room state change',
    build: (room) => buildTestEvent(
      room,
      eventId: r'$e',
      senderId: '@a:x',
      type: EventTypes.RoomName,
      stateKey: '',
      content: {'name': 'Book club'},
    ),
    visible: false,
    visibleWhenShowingHidden: true,
    kind: MessageKind.nonMessage,
  ),
  _Case(
    'reaction',
    build: (room) => buildTestEvent(
      room,
      eventId: r'$e',
      senderId: '@a:x',
      type: EventTypes.Reaction,
      content: {
        'm.relates_to': {
          'rel_type': RelationshipTypes.reaction,
          'event_id': r'$orig',
          'key': '👍',
        },
      },
    ),
    visible: false,
    visibleWhenShowingHidden: false,
    kind: MessageKind.nonMessage,
  ),
];

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:x');
    room = buildTestRoom(client);
    room.setState(
      Event(
        eventId: r'$m',
        type: EventTypes.RoomMember,
        senderId: '@a:x',
        stateKey: '@a:x',
        originServerTs: DateTime.now(),
        content: {'membership': 'join', 'displayname': 'Ada'},
        room: room,
      ),
    );
  });

  group('visibility and description agree across surfaces', () {
    for (final testCase in _cases) {
      test(testCase.name, () {
        final event = testCase.build(room);

        expect(
          isDisplayableTimelineEvent(event, showHiddenMessages: false),
          testCase.visible,
          reason: 'default timeline visibility for "${testCase.name}"',
        );
        expect(
          isDisplayableTimelineEvent(event, showHiddenMessages: true),
          testCase.visibleWhenShowingHidden,
          reason: '"Show hidden messages" visibility for "${testCase.name}"',
        );

        expect(
          isPreviewableLastEvent(event),
          testCase.previewable ?? testCase.visible,
          reason: 'room-list previewability for "${testCase.name}"',
        );

        expect(
          canCarryReadMarker(event),
          isTrue,
          reason: 'read-marker eligibility for "${testCase.name}"',
        );

        final summary = summarize(event);
        expect(summary.kind, testCase.kind);
        if (testCase.text != null) {
          expect(summary.text, testCase.text);
        }
      });
    }
  });

  test('no summary ever leaks the SDK\'s raw fallback text', () {
    for (final testCase in _cases) {
      final text = summarize(testCase.build(room)).text;
      expect(
        text,
        isNot(contains('Unknown message format')),
        reason: 'summary for "${testCase.name}"',
      );
      expect(text, isNotEmpty, reason: 'summary for "${testCase.name}"');
    }
  });

  test('a call summary carries its parsed status, so both surfaces can '
      'pick the same icon', () {
    final event = _msg(
      room,
      const CallSummary(
        callId: 'c1',
        kind: 'video',
        status: CallSummaryStatus.missed,
        durationMs: 0,
      ).toMessageContent(),
    );
    final summary = summarize(event);
    expect(summary.call?.status, CallSummaryStatus.missed);
    expect(summary.call?.kind, 'video');
  });

  test('every other kind leaves call null', () {
    for (final testCase in _cases.where(
      (c) => c.kind != MessageKind.callSummary,
    )) {
      expect(
        summarize(testCase.build(room)).call,
        isNull,
        reason: 'summary for "${testCase.name}"',
      );
    }
  });

  group('the read marker is not a question about what is displayed', () {
    test('everything the app hides can still carry it', () {
      final hidden = <String, Event>{
        'call ring': _msg(room, {'msgtype': callInviteMsgtype, 'body': 'x'}),
        'call decline': _msg(room, {
          'msgtype': callDeclineMsgtype,
          'body': 'x',
        }),
        'verification': _msg(room, {
          'msgtype': 'm.key.verification.request',
          'body': 'x',
        }),
        'edit': _msg(room, {
          'msgtype': MessageTypes.Text,
          'body': '* fixed',
          'm.new_content': {'msgtype': MessageTypes.Text, 'body': 'fixed'},
          'm.relates_to': {
            'rel_type': RelationshipTypes.edit,
            'event_id': r'$orig',
          },
        }),
        'reaction': buildTestEvent(
          room,
          eventId: r'$e',
          senderId: '@a:x',
          type: EventTypes.Reaction,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reaction,
              'event_id': r'$orig',
              'key': '👍',
            },
          },
        ),
        'room state': buildTestEvent(
          room,
          eventId: r'$e',
          senderId: '@a:x',
          type: EventTypes.RoomName,
          stateKey: '',
          content: {'name': 'Book club'},
        ),
        'call membership state': buildTestEvent(
          room,
          eventId: r'$e',
          senderId: '@a:x',
          type: 'm.call.member',
          stateKey: '@a:x',
          content: {'memberships': <Object?>[]},
        ),
        'an event type this app has never heard of': buildTestEvent(
          room,
          eventId: r'$e',
          senderId: '@a:x',
          type: 'com.example.something.new',
          content: {'whatever': true},
        ),
      };
      for (final entry in hidden.entries) {
        expect(
          isDisplayableTimelineEvent(entry.value, showHiddenMessages: false),
          isFalse,
          reason: '${entry.key} should not render',
        );
        expect(
          canCarryReadMarker(entry.value),
          isTrue,
          reason: '${entry.key} must still be receipted',
        );
      }
    });

    test('a still-sending local echo cannot — its id can still change', () {
      for (final status in [EventStatus.sending, EventStatus.error]) {
        final event = Event(
          status: status,
          eventId: r'$pending',
          type: EventTypes.Message,
          senderId: '@a:x',
          originServerTs: DateTime.now(),
          content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
          room: room,
        );
        expect(canCarryReadMarker(event), isFalse, reason: '$status');
      }
    });

    test('a server-accepted event can, at either sent stage', () {
      for (final status in [EventStatus.sent, EventStatus.synced]) {
        final event = Event(
          status: status,
          eventId: r'$real',
          type: EventTypes.Message,
          senderId: '@a:x',
          originServerTs: DateTime.now(),
          content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
          room: room,
        );
        expect(canCarryReadMarker(event), isTrue, reason: '$status');
      }
    });
  });
}
