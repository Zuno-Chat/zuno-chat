import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/reactions.dart';
import 'package:zuno/core/ui/frosted_surface.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/forward_icon.dart';
import 'package:zuno/features/chat/presentation/media_viewer/video_playback.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_chrome.dart';

import '../../../../helpers/date_labels.dart';
import '../../../../helpers/fake_attachments.dart';
import '../../../../helpers/fake_video_player.dart';

void main() {
  late AttachmentServer server;
  late FakeVideoPlayer player;
  late List<String> pressed;

  setUp(() {
    server = installAttachmentServer();
    player = installFakeVideoPlayer();
    pressed = [];
  });

  Event photo({Map<String, Object?> extra = const {}, DateTime? sentAt}) =>
      server.attachment(extra: extra, sentAt: sentAt);

  Future<void> pumpChrome(
    WidgetTester tester,
    Event event, {
    bool visible = true,
    bool respond = true,
    bool more = true,
    bool forward = true,
    VideoPlayback? playback,
    bool muted = false,
    List<ReactionSummary> reactions = const [],
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: zunoViewerTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: Scaffold(
        body: ViewerChrome(
          event: event,
          visible: visible,
          playback: playback,
          muted: muted,
          onBack: () => pressed.add('back'),
          onShare: () => pressed.add('share'),
          onSave: () => pressed.add('save'),
          onToggleMute: () => pressed.add('mute'),
          onInteraction: () => pressed.add('touch'),
          onMore: more ? () => pressed.add('more') : null,
          onReact: respond ? () => pressed.add('react') : null,
          onReply: respond ? () => pressed.add('reply') : null,
          onForward: forward ? () => pressed.add('forward') : null,
          reactions: reactions,
          onToggleReaction: respond
              ? (key) => pressed.add('toggle $key')
              : null,
        ),
      ),
    ),
  );

  testWidgets('shows who sent it and when', (tester) async {
    final sentAt = clock.now();
    final event = photo(sentAt: sentAt);
    await pumpChrome(tester, event);

    expect(
      find.text(event.senderFromMemoryOrFallback.calcDisplayname()),
      findsOneWidget,
    );
    expect(
      find.text(testDateLabels().dayAndTime(sentAt, now: clock.now())),
      findsOneWidget,
    );
  });

  testWidgets('every action reaches its callback', (tester) async {
    await pumpChrome(tester, photo());

    for (final tooltip in [
      'Back',
      'More',
      'React',
      'Reply',
      'Forward',
      'Share',
      'Save',
    ]) {
      await tester.tap(find.byTooltip(tooltip));
    }

    expect(pressed.where((p) => p != 'touch'), [
      'back',
      'more',
      'react',
      'reply',
      'forward',
      'share',
      'save',
    ]);
    expect(pressed.where((p) => p == 'touch'), hasLength(7));
  });

  testWidgets('Forward sits between Reply and Share', (tester) async {
    await pumpChrome(tester, photo());

    double x(String tooltip) => tester.getCenter(find.byTooltip(tooltip)).dx;
    expect(x('Reply'), lessThan(x('Forward')));
    expect(x('Forward'), lessThan(x('Share')));
    expect(
      find.descendant(
        of: find.byTooltip('Forward'),
        matching: find.byType(ForwardIcon),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an item that cannot be forwarded has no Forward', (
    tester,
  ) async {
    await pumpChrome(tester, photo(), forward: false);

    expect(find.byTooltip('Forward'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
  });

  testWidgets('without reply rights the pill keeps Forward, Share and Save', (
    tester,
  ) async {
    await pumpChrome(tester, photo(), respond: false, more: false);

    expect(find.byTooltip('React'), findsNothing);
    expect(find.byTooltip('Reply'), findsNothing);
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
  });

  testWidgets('a gallery item shows its place as dots', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpChrome(
      tester,
      photo(extra: galleryGroupContent(id: 'g', index: 2, count: 7)),
    );

    expect(find.bySemanticsLabel('3 of 7'), findsOneWidget);
    expect(find.text('3 of 7'), findsNothing);
    handle.dispose();
  });

  testWidgets('a long gallery shows its place as text', (tester) async {
    await pumpChrome(
      tester,
      photo(extra: galleryGroupContent(id: 'g', index: 10, count: 12)),
    );

    expect(find.text('11 of 12'), findsOneWidget);
  });

  testWidgets('a photo outside a gallery shows no position', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpChrome(tester, photo());

    expect(find.bySemanticsLabel(RegExp(r'^\d+ of \d+$')), findsNothing);
    handle.dispose();
  });

  testWidgets('a caption shows over the photo', (tester) async {
    await pumpChrome(
      tester,
      server.attachment(body: 'Sunset from the ridge', filename: 'photo.png'),
    );

    expect(find.text('Sunset from the ridge'), findsOneWidget);
  });

  testWidgets('a playing video shows its times and mute', (tester) async {
    final playback = await startedPlayback(
      tester,
      server.video(eventId: r'$clip'),
    );

    await pumpChrome(tester, playback.event, playback: playback);

    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byTooltip('Mute'));
    expect(pressed, ['touch', 'mute']);

    await pumpChrome(tester, playback.event, playback: playback, muted: true);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(player.calls, contains('play'));
    playback.dispose();
  });

  testWidgets('hidden controls do not take taps', (tester) async {
    await pumpChrome(tester, photo(), visible: false);

    await tester.tap(find.byTooltip('Share'), warnIfMissed: false);

    expect(pressed, isEmpty);
  });
  testWidgets('dragging the timeline seeks once, on release', (tester) async {
    final playback = await startedPlayback(
      tester,
      server.video(eventId: r'$scrub'),
    );
    await pumpChrome(tester, playback.event, playback: playback);

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pump();

    expect(player.calls.where((call) => call.startsWith('seek')), hasLength(1));
    playback.dispose();
  });

  group('reactions', () {
    const reactions = [
      ReactionSummary(key: '👍', count: 3, reactedByMe: true),
      ReactionSummary(key: '😂', count: 1, reactedByMe: false),
    ];

    FrostedSurface chipOf(WidgetTester tester, String emoji) =>
        tester.widget<FrostedSurface>(
          find
              .ancestor(
                of: find.text(emoji).last,
                matching: find.byType(FrostedSurface),
              )
              .first,
        );

    testWidgets('shows every reaction with its count, mine marked', (
      tester,
    ) async {
      await pumpChrome(tester, photo(), reactions: reactions);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(chipOf(tester, '😂').highlighted, isFalse);
      expect(
        tester
            .widgetList<FrostedSurface>(find.byType(FrostedSurface))
            .where((surface) => surface.highlighted),
        hasLength(1),
      );
    });

    testWidgets('the React button shows my reaction', (tester) async {
      await pumpChrome(tester, photo(), reactions: reactions);

      expect(
        find.descendant(of: find.byTooltip('React'), matching: find.text('👍')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
    });

    testWidgets('without a reaction of mine the React button shows its icon', (
      tester,
    ) async {
      await pumpChrome(
        tester,
        photo(),
        reactions: const [
          ReactionSummary(key: '😂', count: 1, reactedByMe: false),
        ],
      );

      expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    });

    testWidgets('tapping a reaction toggles it', (tester) async {
      await pumpChrome(tester, photo(), reactions: reactions);

      await tester.tap(find.text('1'));

      expect(pressed.where((p) => p != 'touch'), ['toggle 😂']);
    });

    testWidgets('without reply rights reactions show but cannot be tapped', (
      tester,
    ) async {
      await pumpChrome(tester, photo(), reactions: reactions, respond: false);

      await tester.tap(find.text('1'));

      expect(find.text('3'), findsOneWidget);
      expect(pressed.where((p) => p != 'touch'), isEmpty);
    });
  });
}
