import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/currently_open_room_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/notifications/messages/conversation_tones.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_audio_session.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_open_room.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/test_clock.dart';

Event ourText(
  Room room, {
  String eventId = r'$1',
  EventStatus status = EventStatus.sent,
  String senderId = '@me:x',
  String type = EventTypes.Message,
  Map<String, Object?> content = const {
    'msgtype': MessageTypes.Text,
    'body': 'hi',
  },
}) => buildTestEvent(
  room,
  eventId: eventId,
  senderId: senderId,
  type: type,
  status: status,
  content: content,
);

void main() {
  late RecordedMethodCalls native;

  setUp(() => native = recordMethodChannel('zuno/conversation_tones'));

  List<Object?> tonesPlayed() => native.valuesOf('play', 'tone');

  group('the tone player', () {
    var now = DateTime(2030);
    var enabled = true;
    var recording = false;
    late ConversationTonePlayer player;
    final clockedTest = testsOnClock(() => now);

    setUp(() {
      now = DateTime(2030);
      enabled = true;
      recording = false;
      player = ConversationTonePlayer(
        enabled: () => enabled,
        recording: () => recording,
      );
    });

    clockedTest('asks native to play the tone by name', () async {
      await player.play(ConversationTone.incoming);
      await player.play(ConversationTone.sent);

      expect(tonesPlayed(), ['incoming', 'sent']);
    });

    clockedTest('plays nothing with the switch off', () async {
      enabled = false;

      await player.play(ConversationTone.incoming);

      expect(native.calls, isEmpty);
    });

    clockedTest('plays nothing while recording', () async {
      recording = true;

      await player.play(ConversationTone.sent);

      expect(native.calls, isEmpty);
    });

    clockedTest('a burst plays once', () async {
      await player.play(ConversationTone.incoming);
      now = now.add(const Duration(seconds: 1));
      await player.play(ConversationTone.incoming);
      await player.play(ConversationTone.sent);
      now = now.add(const Duration(seconds: 1));
      await player.play(ConversationTone.incoming);

      expect(tonesPlayed(), ['incoming', 'sent', 'incoming']);
    });

    clockedTest(
      'a gallery plays once, however slowly its items arrive',
      () async {
        await player.play(ConversationTone.sent, gallery: 'g');
        now = now.add(const Duration(seconds: 3));
        await player.play(ConversationTone.sent, gallery: 'g');
        await player.play(ConversationTone.sent, gallery: 'h');

        expect(tonesPlayed(), ['sent', 'sent']);
      },
    );

    clockedTest('where tones need the audio session, a tone plays inside '
        'it', () async {
      final log = <String>[];
      recordMethodChannel(
        'zuno/conversation_tones',
        reply: (_) => log.add('play'),
      );
      final inSession = ConversationTonePlayer(
        enabled: () => true,
        recording: () => false,
        session: fakeMediaAudioSession(FakeAudioSessionPort(log)),
      );

      await inSession.play(ConversationTone.incoming);

      expect(log, ['configure tone', 'active', 'play', 'inactive']);
    });

    clockedTest('a missing native player is a silent no-op', () async {
      recordMethodChannel(
        'zuno/conversation_tones',
        reply: (_) => throw MissingPluginException(),
      );
      final reports = await reportsDuring(
        () => player.play(ConversationTone.incoming),
      );

      expect(reports, isEmpty);
    });
  });

  group('sentToneFor', () {
    late Client client;
    late Room room;

    setUp(() {
      client = buildTestClient(userId: '@me:x');
      room = buildTestRoom(client);
    });

    Event ours({
      EventStatus status = EventStatus.sent,
      String senderId = '@me:x',
      String type = EventTypes.Message,
      Map<String, Object?> content = const {
        'msgtype': MessageTypes.Text,
        'body': 'hi',
      },
    }) => ourText(
      room,
      status: status,
      senderId: senderId,
      type: type,
      content: content,
    );

    bool tone(Event event, {String? openRoomId}) =>
        sentToneFor(event, userId: '@me:x', openRoomId: openRoomId ?? room.id);

    test('plays for our message in the open chat once the server has it', () {
      expect(tone(ours()), isTrue);
    });

    test('waits for the server, and a failed send stays silent', () {
      expect(tone(ours(status: EventStatus.sending)), isFalse);
      expect(tone(ours(status: EventStatus.error)), isFalse);
    });

    test('stays silent for our message sent from another device', () {
      expect(tone(ours(status: EventStatus.synced)), isFalse);
    });

    test('stays silent outside the open chat', () {
      expect(tone(ours(), openRoomId: '!elsewhere:x'), isFalse);
      expect(sentToneFor(ours(), userId: '@me:x', openRoomId: null), isFalse);
    });

    test('stays silent for someone else\'s message', () {
      expect(tone(ours(senderId: '@a:x')), isFalse);
    });

    test('stays silent for edits and reactions', () {
      expect(
        tone(
          ours(
            content: {
              'msgtype': MessageTypes.Text,
              'body': '* hi',
              'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$0'},
            },
          ),
        ),
        isFalse,
      );
      expect(
        tone(
          ours(
            type: EventTypes.Reaction,
            content: {
              'm.relates_to': {
                'rel_type': 'm.annotation',
                'event_id': r'$0',
                'key': '👍',
              },
            },
          ),
        ),
        isFalse,
      );
    });
  });

  group('the sent tone', () {
    late Client client;
    late Room room;
    late ProviderContainer container;
    var now = DateTime(2030);

    setUp(
      () => withClock(Clock(() => now), () async {
        now = DateTime(2030);
        client = buildTestClient(userId: '@me:x');
        room = buildTestRoom(client);
        container = await containerWithPreferences(
          {},
          overrides: [
            matrixClientProvider.overrideWithValue(client),
            fixedOpenRoom(room.id),
          ],
        );
        container
          ..read(currentlyOpenRoomIdProvider)
          ..read(conversationTonePlayerProvider);
      }),
    );

    test(
      'plays when our message in the open chat reaches the server',
      () async {
        client.onTimelineEvent.add(ourText(room));
        await pumpEventQueue();

        expect(tonesPlayed(), ['sent']);
      },
    );

    test('a gallery sent slowly plays one tone', () async {
      for (final index in [0, 1]) {
        client.onTimelineEvent.add(
          ourText(
            room,
            eventId: '\$$index',
            content: {
              'msgtype': MessageTypes.Image,
              'body': 'photo.jpg',
              ...galleryGroupContent(id: 'g', index: index, count: 2),
            },
          ),
        );
        await pumpEventQueue();
        now = now.add(const Duration(seconds: 3));
      }

      expect(tonesPlayed(), ['sent']);
    });

    test('stays silent once we have left the chat', () async {
      (container.read(
        currentlyOpenRoomIdProvider.notifier,
      ) as FixedOpenRoomNotifier).open(null);

      client.onTimelineEvent.add(ourText(room));
      await pumpEventQueue();

      expect(native.calls, isEmpty);
    });
  });
}
