import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/matrix/quoted_message_box.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/date_divider.dart';
import 'package:zuno/features/chat/presentation/file_name_text.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';
import 'package:zuno/features/chat/presentation/message_contents/call_summary_tile.dart';
import 'package:zuno/features/chat/presentation/message_contents/file_message.dart';
import 'package:zuno/features/chat/presentation/message_contents/reactions_row.dart';
import 'package:zuno/features/chat/presentation/message_contents/reply_quote.dart';
import 'package:zuno/features/chat/presentation/message_contents/voice_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';
import 'package:zuno/features/chat/presentation/reply_target_cache.dart';

import '../../../helpers/fake_matrix.dart';

const me = '@me:example.org';
const bob = '@bob:example.org';
const meta = MessageMeta(time: '09:41', own: false);

Widget _wrap(Widget child) => MaterialApp(
  theme: zunoLightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  late Room room;
  late StoredEventsFakeDatabaseApi db;
  final colors = zunoLightTheme.colorScheme;
  final noon = DateTime(2026, 9, 20, 12);

  setUp(() {
    db = StoredEventsFakeDatabaseApi();
    room = buildTestRoom(buildTestClient(userId: me, database: db))
      ..partial = false;
    room.setState(
      User(bob, membership: 'join', displayName: 'Bob', room: room),
    );
  });

  testWidgets('a missed call is drawn in the error color', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CallSummaryTile(
          summary: CallSummary(
            callId: 'c1',
            kind: 'voice',
            status: CallSummaryStatus.missed,
            durationMs: 0,
          ),
          own: false,
          meta: meta,
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.call_missed));
    expect(icon.color, colors.error);
    final label = tester.widget<Text>(find.textContaining('issed'));
    expect(label.style!.color, colors.error);
  });

  testWidgets('a finished call shows its length in the muted color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const CallSummaryTile(
          summary: CallSummary(
            callId: 'c1',
            kind: 'video',
            status: CallSummaryStatus.ended,
            durationMs: 252000,
          ),
          own: false,
          meta: meta,
        ),
      ),
    );
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(find.text('Video call'), findsOneWidget);
    final length = tester.widget<Text>(find.text('04:12'));
    expect(length.style!.color, colors.onSurfaceVariant);
    expect(find.byType(MessageMeta), findsOneWidget);
  });

  testWidgets('a file name is medium weight and keeps FileNameText', (
    tester,
  ) async {
    final event = buildTestEvent(
      room,
      eventId: r'$f',
      senderId: bob,
      originServerTs: noon,
      content: {
        'msgtype': 'm.file',
        'body': 'Boiler manual.pdf',
        'info': {'size': 1258291},
      },
    );
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 240,
          child: FileMessage(event: event, own: false, meta: meta),
        ),
      ),
    );
    final name = tester.widget<FileNameText>(find.byType(FileNameText));
    expect(name.style!.fontWeight, FontWeight.w500);
    expect(find.text('1.2 MB'), findsOneWidget);
    expect(find.byType(MessageMeta), findsOneWidget);
  });

  testWidgets('reaction chips are ink surfaces; mine is tinted', (
    tester,
  ) async {
    final message = buildTestEvent(
      room,
      eventId: r'$m1',
      senderId: bob,
      originServerTs: noon,
      content: {'msgtype': 'm.text', 'body': 'hi'},
    );
    Event reaction(String id, String key, String sender) => buildTestEvent(
      room,
      eventId: id,
      senderId: sender,
      type: EventTypes.Reaction,
      originServerTs: noon,
      content: {
        'm.relates_to': {
          'rel_type': 'm.annotation',
          'event_id': r'$m1',
          'key': key,
        },
      },
    );
    db.events = [
      reaction(r'$r2', '🎉', me),
      reaction(r'$r1', '👍', bob),
      message,
    ];
    final timeline = (await tester.runAsync(room.getTimeline))!;
    addTearDown(timeline.cancelSubscriptions);

    await tester.pumpWidget(
      _wrap(ReactionsRow(event: message, timeline: timeline)),
    );

    Material chip(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    expect(chip('👍 1').color, colors.surface);
    expect(chip('🎉 1').color, colors.secondaryContainer);
    expect(
      find.descendant(
        of: find.byType(ReactionsRow),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('the quote fill is the blended surface, never a border', (
    tester,
  ) async {
    final target = buildTestEvent(
      room,
      eventId: r'$t',
      senderId: bob,
      originServerTs: noon,
      content: {'msgtype': 'm.text', 'body': 'the original'},
    );
    db.events = [target];
    final timeline = (await tester.runAsync(room.getTimeline))!;
    addTearDown(timeline.cancelSubscriptions);

    await tester.pumpWidget(
      _wrap(
        ReplyQuote(
          timeline: timeline,
          eventId: r'$t',
          target: target,
          cache: ReplyTargetCache((_) async => null),
          own: true,
        ),
      ),
    );
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(QuotedMessageBox),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(
      decoration.color,
      quoteFill(
        surface: colors.surface,
        bubble: bubbleFill(zunoLightTheme, own: true),
      ),
    );
    expect(decoration.border, isNull);
    final name = tester.widget<Text>(find.text('Bob'));
    expect(name.style!.color, colors.primary);
    expect(name.style!.fontWeight, FontWeight.w500);
  });

  testWidgets('a reply quote never looks up from build', (tester) async {
    var lookups = 0;
    db.events = [];
    final timeline = (await tester.runAsync(room.getTimeline))!;
    addTearDown(timeline.cancelSubscriptions);
    final cache = ReplyTargetCache((_) async {
      lookups++;
      return null;
    });
    late void Function() rebuild;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = () => setState(() {});
            return ReplyQuote(
              timeline: timeline,
              eventId: r'$gone',
              target: null,
              cache: cache,
              own: false,
            );
          },
        ),
      ),
    );
    expect(find.text('Loading…'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      rebuild();
      await tester.pump();
    }

    expect(lookups, 1);
    expect(find.text('Original message not available'), findsOneWidget);
  });

  testWidgets('the day label is a quiet pill', (tester) async {
    await tester.pumpWidget(_wrap(const DateDivider(label: 'Today')));
    final text = tester.widget<Text>(find.text('Today'));
    expect(text.style!.color, colors.onSurfaceVariant);
    expect(text.strutStyle!.forceStrutHeight, isTrue);
  });

  testWidgets('the voice play button is a primaryContainer circle', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channels = [
      const MethodChannel('xyz.luan/audioplayers'),
      const MethodChannel('xyz.luan/audioplayers.global'),
    ];
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
    }
    addTearDown(() {
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    final event = buildTestEvent(
      room,
      eventId: r'$v',
      senderId: bob,
      originServerTs: noon,
      content: {
        'msgtype': 'm.audio',
        'body': 'voice.ogg',
        'url': 'mxc://example.org/voice',
        'info': {'duration': 42000, 'mimetype': 'audio/ogg'},
        'org.matrix.msc3245.voice': <String, Object?>{},
      },
    );

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 240,
          child: VoiceMessage(event: event, own: false, meta: meta),
        ),
      ),
    );

    final circle = tester.widget<Material>(
      find
          .ancestor(
            of: find.byIcon(Icons.play_arrow),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(circle.color, colors.primaryContainer);
    expect(circle.shape, const CircleBorder());
    expect(tester.getSize(find.byWidget(circle)), const Size(40, 40));
    expect(find.byType(MessageMeta), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
