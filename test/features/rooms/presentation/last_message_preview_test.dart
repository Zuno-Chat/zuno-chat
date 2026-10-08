import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/undecryptable_message.dart';
import 'package:zuno/features/rooms/presentation/last_message_preview.dart';

import '../../../helpers/fake_matrix.dart';

class _FakeEncryption extends Fake implements Encryption {
  final decrypted = <Event>[];
  int attempts = 0;

  @override
  Future<Event> decryptRoomEvent(
    Event event, {
    bool store = false,
    EventUpdateType updateType = EventUpdateType.timeline,
  }) async {
    attempts++;
    return decrypted.isEmpty ? event : decrypted.removeAt(0);
  }
}

class _DecryptingClient extends Client {
  _DecryptingClient(this.fakeEncryption)
    : super(
        'test',
        database: TimelineCapableFakeDatabaseApi(),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

  final _FakeEncryption fakeEncryption;

  @override
  Encryption? get encryption => fakeEncryption;
}

void main() {
  late Room room;
  late _FakeEncryption encryption;

  setUp(() {
    encryption = _FakeEncryption();
    final client = _DecryptingClient(encryption);
    client.setUserId('@me:example.org');
    room = buildTestRoom(client)..partial = false;
  });

  Future<void> pump(WidgetTester tester, Event? event) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSecurityFactsProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: zunoLightTheme,
          home: Scaffold(
            body: DefaultTextStyle.merge(
              style: zunoLightTheme.textTheme.bodyMedium,
              child: LastMessagePreview(room: room, event: event),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Event message(Map<String, Object?> content) => buildTestEvent(
    room,
    eventId: r'$e',
    senderId: '@bob:example.org',
    content: content,
  );

  testWidgets('a text preview is strut-locked to the inherited style', (
    tester,
  ) async {
    await pump(tester, message({'msgtype': 'm.text', 'body': 'สวัสดี'}));

    final text = tester.widget<Text>(find.text('สวัสดี'));
    expect(text.strutStyle?.forceStrutHeight, isTrue);
    expect(text.strutStyle?.fontSize, 14);
  });

  testWidgets('an icon-and-label preview is strut-locked too', (tester) async {
    await pump(
      tester,
      message({'msgtype': 'm.image', 'body': 'photo.jpg', 'url': 'mxc://x/y'}),
    );

    final texts = tester.widgetList<Text>(find.byType(Text));
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(text.strutStyle?.forceStrutHeight, isTrue);
    }
  });

  testWidgets('no last event says so, strut-locked', (tester) async {
    await pump(tester, null);

    final text = tester.widget<Text>(find.text('No messages'));
    expect(text.strutStyle?.forceStrutHeight, isTrue);
  });

  Event encrypted() => buildTestEvent(
    room,
    eventId: r'$enc',
    senderId: '@bob:example.org',
    type: EventTypes.Encrypted,
    content: {'algorithm': 'm.megolm.v1.aes-sha2', 'ciphertext': 'x'},
  );

  Color? iconColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).color;

  ColorScheme colors(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(LastMessagePreview))).colorScheme;

  testWidgets('each attachment shows its icon and label', (tester) async {
    for (final (content, icon, label) in [
      (
        {'msgtype': 'm.video', 'body': 'clip.mp4', 'url': 'mxc://x/v'},
        Icons.videocam_outlined,
        'Video',
      ),
      (
        {
          'msgtype': 'm.audio',
          'body': 'voice.ogg',
          'url': 'mxc://x/a',
          'org.matrix.msc3245.voice': <String, Object?>{},
        },
        Icons.mic_none_outlined,
        'Voice message',
      ),
      (
        {'msgtype': 'm.file', 'body': 'notes.pdf', 'url': 'mxc://x/f'},
        Icons.insert_drive_file_outlined,
        'notes.pdf',
      ),
      (
        {'msgtype': 'm.location', 'body': 'Here', 'geo_uri': 'geo:1,2'},
        Icons.location_on_outlined,
        'Location',
      ),
      (
        {
          'msgtype': 'im.zuno.live_location',
          'body': 'Live location for 1 hour',
          'share_id': 'share1',
          'ends_ts': 1700003600000,
        },
        Icons.share_location_outlined,
        'Live location',
      ),
    ]) {
      await pump(tester, message(content));

      expect(find.byIcon(icon), findsOneWidget, reason: label);
      expect(find.text(label), findsOneWidget, reason: label);
      expect(iconColor(tester), colors(tester).onSurfaceVariant);
    }
  });

  testWidgets('a deleted message says so in italics', (tester) async {
    final event = message({'msgtype': 'm.text', 'body': 'gone'});
    event.unsigned = {
      'redacted_because': {
        'event_id': r'$redaction',
        'sender': '@bob:example.org',
        'type': EventTypes.Redaction,
        'origin_server_ts': 0,
        'content': <String, Object?>{},
      },
    };
    await pump(tester, event);

    final text = tester.widget<Text>(find.text('Message deleted'));
    expect(text.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('a message that is not shown in the chat leaves the line '
      'blank', (tester) async {
    await pump(
      tester,
      buildTestEvent(
        room,
        eventId: r'$name',
        senderId: '@bob:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Chess'},
      ),
    );

    expect(find.text(''), findsOneWidget);
  });

  group('a call summary', () {
    Event summary(String kind, CallSummaryStatus status) => message(
      CallSummary(
        callId: 'c1',
        kind: kind,
        status: status,
        durationMs: 65000,
      ).toMessageContent(),
    );

    testWidgets('a missed call is marked in the error colour', (tester) async {
      await pump(tester, summary('voice', CallSummaryStatus.missed));

      expect(find.byIcon(Icons.call_missed_outlined), findsOneWidget);
      expect(find.text('Missed Voice call'), findsOneWidget);
      expect(iconColor(tester), colors(tester).error);
      expect(
        tester.widget<Text>(find.text('Missed Voice call')).style?.color,
        colors(tester).error,
      );

      await pump(tester, summary('video', CallSummaryStatus.missed));
      expect(find.byIcon(Icons.missed_video_call_outlined), findsOneWidget);
    });

    testWidgets('other calls use a plain icon for their kind', (tester) async {
      for (final (kind, status, icon) in [
        ('voice', CallSummaryStatus.declined, Icons.call_end_outlined),
        ('video', CallSummaryStatus.declined, Icons.call_end_outlined),
        ('voice', CallSummaryStatus.ended, Icons.call_outlined),
        ('video', CallSummaryStatus.ended, Icons.videocam_outlined),
      ]) {
        await pump(tester, summary(kind, status));

        expect(find.byIcon(icon), findsOneWidget, reason: '$kind $status');
        expect(iconColor(tester), colors(tester).onSurfaceVariant);
      }
      expect(find.text('Video call · 1:05'), findsOneWidget);
    });
  });

  group('a message that cannot be read yet', () {
    testWidgets('says so while it stays locked', (tester) async {
      await pump(tester, encrypted());

      expect(find.byType(UndecryptablePreviewText), findsOneWidget);
      expect(encryption.attempts, 1);
    });

    testWidgets('shows the text as soon as it can be decrypted', (
      tester,
    ) async {
      encryption.decrypted.add(
        message({'msgtype': 'm.text', 'body': 'See you at 8'}),
      );
      await pump(tester, encrypted());
      await tester.pump();

      expect(find.text('See you at 8'), findsOneWidget);
      expect(room.lastEvent?.body, 'See you at 8');
    });

    testWidgets('tries again once a key arrives, after a short pause', (
      tester,
    ) async {
      await pump(tester, encrypted());
      expect(encryption.attempts, 1);

      encryption.decrypted.add(
        message({'msgtype': 'm.text', 'body': 'See you at 8'}),
      );
      room.onSessionKeyReceived.add('s1');
      room.onSessionKeyReceived.add('s2');
      await tester.pump(const Duration(milliseconds: 200));
      expect(encryption.attempts, 1);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(encryption.attempts, 2);
      expect(find.text('See you at 8'), findsOneWidget);
    });

    testWidgets('stops waiting for keys once it is gone', (tester) async {
      await pump(tester, encrypted());
      await tester.pumpWidget(const SizedBox());

      room.onSessionKeyReceived.add('s1');
      await tester.pump(const Duration(seconds: 1));

      expect(encryption.attempts, 1);
    });
  });
}
