import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/media_audio_session.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/features/chat/data/chat_timeline.dart';
import 'package:zuno/features/chat/presentation/media_viewer/media_viewer_page.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_chrome.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_photo.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_video.dart';

import '../../../../helpers/fake_attachments.dart';
import '../../../../helpers/fake_audio_session.dart';
import '../../../../helpers/fake_matrix.dart';
import '../../../../helpers/fake_media_feed.dart';
import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/native_method_calls.dart';
import '../../../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;
  late FakeVideoPlayer player;
  late RecordedMethodCalls platform;
  late List<Event> replies;
  late List<String?> fetches;
  late Timeline timeline;

  setUp(() async {
    server = installAttachmentServer();
    player = installFakeVideoPlayer();
    platform = recordChannel(SystemChannels.platform);
    replies = [];
    fetches = [];
    timeline = await (buildTestRoom(
      buildTestClient(database: TimelineCapableFakeDatabaseApi()),
    )..partial = false).getTimeline();
    addTearDown(timeline.cancelSubscriptions);
  });

  List<Object?> systemUiModes() =>
      platform.argsOf('SystemChrome.setEnabledSystemUIMode');

  DateTime at(int ts) => DateTime.fromMillisecondsSinceEpoch(ts);

  Event photo(String id, int ts) =>
      server.attachment(eventId: id, sentAt: at(ts));

  Event video(String id, int ts) => server.video(eventId: id, sentAt: at(ts));

  Future<void> openViewer(
    WidgetTester tester, {
    required Map<String?, RoomMediaBatch> pages,
    required Event opened,
    ValueListenable<Timeline?>? chatTimeline,
    int pageSize = 40,
    bool preload = false,
    Map<String?, Completer<void>> gates = const {},
  }) async {
    final feed = fakeMediaFeed(
      server.room,
      pages,
      pageSize: pageSize,
      calls: fetches,
      gates: gates,
    );
    if (preload) await feed.loadMore();
    final chat = ViewerChat(
      room: server.room,
      timeline: chatTimeline ?? ValueNotifier(timeline),
      startReply: replies.add,
      startEdit: (_) {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomMediaFeedProvider(server.room).overrideWithValue(feed),
          mediaAudioSessionProvider.overrideWithValue(
            fakeMediaAudioSession(FakeAudioSessionPort()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      openMediaViewer(context, chat: chat, opened: opened),
                  child: const Text('chat'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('chat'));
    await tester.pump();
    await tester.pump(ZunoDurations.page * 2);
  }

  ViewerChrome chrome(WidgetTester tester) =>
      tester.widget<ViewerChrome>(find.byType(ViewerChrome));

  String shown(WidgetTester tester) => chrome(tester).event.eventId;

  String onScreen(WidgetTester tester) =>
      tester.widget<ViewerPhoto>(find.byType(ViewerPhoto)).event.eventId;

  Future<void> swipeToOlder(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> swipeToNewer(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> zoomIn(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(ViewerPhoto));
    await tester.tapAt(center);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(ZunoDurations.standard);
  }

  void delete(String eventId) => server.client.onTimelineEvent.add(
    buildTestRedaction(server.room, eventId),
  );

  Future<void> closeGesture(WidgetTester tester, double distance) async {
    await tester.drag(
      find.byType(PageView),
      Offset(0, distance),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await tester.pump(ZunoDurations.page * 2);
  }

  bool viewerOpen() => find.byType(MediaViewerPage).evaluate().isNotEmpty;

  testWidgets('opens on the tapped photo, filling and centered on the whole '
      'screen', (tester) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened], nextBatch: null),
      },
      opened: opened,
    );

    expect(shown(tester), r'$a');
    expect(
      tester.getRect(find.byType(ViewerPhoto)),
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
    );
  });

  testWidgets('swiping shows the next newer item', (tester) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [photo(r'$b', 2), opened], nextBatch: null),
      },
      opened: opened,
    );

    await swipeToNewer(tester);

    expect(shown(tester), r'$b');
  });

  testWidgets('near the oldest item older ones load, and the item on screen '
      'stays', (tester) async {
    final opened = photo(r'$c', 3);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened], nextBatch: 'b1'),
        'b1': (events: [photo(r'$b', 2), photo(r'$a', 1)], nextBatch: null),
      },
      opened: opened,
      pageSize: 1,
    );
    await tester.pump();

    expect(fetches, [null, 'b1']);
    expect(shown(tester), r'$c');
    expect(onScreen(tester), r'$c');
  });

  testWidgets('someone deleting the item on screen moves to its neighbor, and '
      'deleting the last one closes the viewer', (tester) async {
    final opened = photo(r'$b', 2);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened, photo(r'$a', 1)], nextBatch: null),
      },
      opened: opened,
    );
    expect(shown(tester), r'$b');

    delete(r'$b');
    await tester.pump();
    await tester.pump();
    expect(shown(tester), r'$a');

    delete(r'$a');
    await tester.pump();
    await tester.pump(ZunoDurations.page * 2);
    await tester.pump();
    expect(viewerOpen(), isFalse);
  });

  testWidgets('a tap hides the controls and the system bars, another shows '
      'them', (tester) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened], nextBatch: null),
      },
      opened: opened,
    );
    expect(chrome(tester).visible, isTrue);

    await tester.tap(find.byType(ViewerPhoto));
    await tester.pump(kDoubleTapTimeout);
    expect(chrome(tester).visible, isFalse);
    expect(systemUiModes().last, 'SystemUiMode.immersiveSticky');

    await tester.tap(find.byType(ViewerPhoto));
    await tester.pump(kDoubleTapTimeout);
    expect(chrome(tester).visible, isTrue);
    expect(systemUiModes().last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('dragging down far enough closes the viewer; a short drag '
      'springs back', (tester) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened], nextBatch: null),
      },
      opened: opened,
    );

    await closeGesture(tester, 40);
    expect(viewerOpen(), isTrue);
    expect(tester.getTopLeft(find.byType(ViewerPhoto)), Offset.zero);

    await closeGesture(tester, 300);
    expect(viewerOpen(), isFalse);
    expect(find.text('chat'), findsOneWidget);
  });

  testWidgets('dragging down shows the chat under the viewer, and letting '
      'go covers it again', (tester) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened], nextBatch: null),
      },
      opened: opened,
    );
    expect(find.text('chat'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('chat'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    await tester.pump(ZunoDurations.page * 2);
    expect(viewerOpen(), isTrue);
    expect(find.text('chat'), findsNothing);
  });

  testWidgets('a zoomed photo neither pages nor closes on drag', (
    tester,
  ) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [photo(r'$b', 2), opened], nextBatch: null),
      },
      opened: opened,
    );
    await zoomIn(tester);

    await swipeToNewer(tester);
    expect(shown(tester), r'$a');

    await closeGesture(tester, 300);
    expect(viewerOpen(), isTrue);
  });

  testWidgets('Back closes the viewer and restores the system bars', (
    tester,
  ) async {
    final opened = photo(r'$a', 1);
    await openViewer(
      tester,
      pages: {
        null: (events: [opened], nextBatch: null),
      },
      opened: opened,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(ZunoDurations.page * 2);

    expect(viewerOpen(), isFalse);
    expect(systemUiModes().last, 'SystemUiMode.edgeToEdge');
  });

  group('video', () {
    testWidgets('an opened video plays at once', (tester) async {
      final opened = video(r'$v', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );

      await pumpUntil(
        tester,
        () => player.calls.contains('play'),
        reason: 'the video to play',
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(ZunoDurations.page);
    });

    testWidgets('a swiped-to video waits for Play and downloads nothing', (
      tester,
    ) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [video(r'$v', 2), opened], nextBatch: null),
        },
        opened: opened,
      );

      await swipeToNewer(tester);

      expect(find.byType(ViewerVideo), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(player.opened, isEmpty);
      expect(server.downloads.where((url) => url.path.endsWith('/v')), isEmpty);
    });

    testWidgets('closing while a video plays disposes its player', (
      tester,
    ) async {
      final opened = video(r'$v', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );
      await pumpUntil(
        tester,
        () => player.calls.contains('play'),
        reason: 'the video to play',
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(ZunoDurations.page);

      await pumpUntil(
        tester,
        () => player.calls.contains('dispose'),
        reason: 'the player to be disposed',
      );
    });

    testWidgets('controls hide 3 seconds after a video starts playing', (
      tester,
    ) async {
      final opened = video(r'$v', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );
      await pumpUntil(
        tester,
        () => player.calls.contains('play'),
        reason: 'the video to play',
      );
      expect(chrome(tester).visible, isTrue);

      await tester.pump(const Duration(seconds: 3));
      expect(chrome(tester).visible, isFalse);

      Navigator.of(tester.element(find.byType(MediaViewerPage))).pop();
      await tester.pump();
      await tester.pump(ZunoDurations.page);
    });
  });

  group('actions', () {
    testWidgets('Reply hands the photo on screen to the chat', (tester) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );

      await tester.tap(find.byTooltip('Reply'));

      expect(replies.map((e) => e.eventId), [r'$a']);
    });

    testWidgets(
      "without the chat's timeline React, Reply and More are hidden",
      (tester) async {
        final opened = photo(r'$a', 1);
        await openViewer(
          tester,
          pages: {
            null: (events: [opened], nextBatch: null),
          },
          opened: opened,
          chatTimeline: ValueNotifier(null),
        );

        expect(find.byTooltip('React'), findsNothing);
        expect(find.byTooltip('Reply'), findsNothing);
        expect(find.byTooltip('More'), findsNothing);
        expect(find.byTooltip('Save'), findsOneWidget);
      },
    );

    testWidgets('without posting rights React and Reply are hidden', (
      tester,
    ) async {
      setPowerLevels(server.room, {
        'events_default': 50,
        'users': {'@creator:example.org': 100},
      });
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );

      expect(find.byTooltip('React'), findsNothing);
      expect(find.byTooltip('Reply'), findsNothing);
      expect(find.byTooltip('More'), findsOneWidget);
    });
  });

  group('keeping its place and state', () {
    testWidgets('opening an item the feed already holds shows that item', (
      tester,
    ) async {
      final opened = photo(r'$b', 2);
      await openViewer(
        tester,
        pages: {
          null: (
            events: [photo(r'$c', 3), opened, photo(r'$a', 1)],
            nextBatch: null,
          ),
        },
        opened: opened,
        preload: true,
      );

      expect(shown(tester), r'$b');
      expect(onScreen(tester), r'$b');
    });

    testWidgets('older items arriving during a swipe keep the swiped-to item '
        'on screen', (tester) async {
      final opened = photo(r'$d', 4);
      final gate = Completer<void>();
      await openViewer(
        tester,
        pages: {
          null: (events: [opened, photo(r'$c', 3)], nextBatch: 'b1'),
          'b1': (events: [photo(r'$b', 2), photo(r'$a', 1)], nextBatch: null),
        },
        opened: opened,
        pageSize: 2,
        gates: {'b1': gate},
      );
      expect(fetches, [null, 'b1']);

      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(shown(tester), r'$c');
      expect(onScreen(tester), r'$c');
    });

    testWidgets('a failed load at the oldest edge is not retried on its own, '
        'and a swipe there tries again', (tester) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: 'b1'),
        },
        opened: opened,
        pageSize: 1,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(fetches, [null, 'b1']);

      await swipeToOlder(tester);

      expect(fetches, [null, 'b1', 'b1']);
    });

    testWidgets('deleting a zoomed photo leaves its neighbor swipeable', (
      tester,
    ) async {
      final opened = photo(r'$b', 2);
      await openViewer(
        tester,
        pages: {
          null: (
            events: [photo(r'$c', 3), opened, photo(r'$a', 1)],
            nextBatch: null,
          ),
        },
        opened: opened,
      );
      await zoomIn(tester);

      delete(r'$b');
      await tester.pump();
      await tester.pump();
      expect(shown(tester), r'$c');

      await swipeToOlder(tester);
      expect(shown(tester), r'$a');
    });

    testWidgets('deleting the last item while a sheet is open closes the sheet '
        'and the viewer', (tester) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );
      await tester.tap(find.byTooltip('React'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BottomSheet), findsOneWidget);

      delete(r'$a');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(BottomSheet), findsNothing);
      expect(viewerOpen(), isFalse);
      expect(find.text('chat'), findsOneWidget);
    });

    testWidgets('a deletion while the viewer closes leaves the chat open', (
      tester,
    ) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 100));
      delete(r'$a');
      await tester.pump();
      await tester.pump(ZunoDurations.page * 2);

      expect(viewerOpen(), isFalse);
      expect(find.text('chat'), findsOneWidget);
    });

    testWidgets('closing restores the system bars at once', (tester) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );
      platform.clear();

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(systemUiModes(), contains('SystemUiMode.edgeToEdge'));
      await tester.pump(ZunoDurations.page * 2);
    });

    testWidgets('the status bar stays light over the viewer', (tester) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .ancestor(
              of: find.byType(ViewerChrome),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value, SystemUiOverlayStyle.light);
    });

    testWidgets("actions appear once the chat's timeline arrives", (
      tester,
    ) async {
      final chatTimeline = ValueNotifier<Timeline?>(null);
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
        chatTimeline: chatTimeline,
      );
      expect(find.byTooltip('React'), findsNothing);

      chatTimeline.value = timeline;
      await tester.pump();

      expect(find.byTooltip('React'), findsOneWidget);
      expect(find.byTooltip('More'), findsOneWidget);
    });

    testWidgets('only the opened item flies back to the chat', (tester) async {
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [photo(r'$b', 2), opened], nextBatch: null),
        },
        opened: opened,
      );
      Finder heroes() => find.descendant(
        of: find.byType(MediaViewerPage),
        matching: find.byType(Hero),
      );
      expect(heroes(), findsOneWidget);

      await swipeToNewer(tester);

      expect(heroes(), findsNothing);
    });
  });

  group('video controls', () {
    testWidgets('closing pauses a playing video at once', (tester) async {
      final opened = video(r'$v', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );
      await pumpUntil(
        tester,
        () => player.calls.contains('play'),
        reason: 'the video to play',
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(player.calls.last, 'pause');
      await tester.pump(ZunoDurations.page * 2);
    });

    testWidgets('touching the video controls keeps them up', (tester) async {
      final opened = video(r'$v', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
      );
      await pumpUntil(
        tester,
        () => player.calls.contains('play'),
        reason: 'the video to play',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Mute'));
      await tester.pump(const Duration(seconds: 2));
      expect(chrome(tester).visible, isTrue);

      await tester.pump(const Duration(milliseconds: 1500));
      expect(chrome(tester).visible, isFalse);

      Navigator.of(tester.element(find.byType(MediaViewerPage))).pop();
      await tester.pump();
      await tester.pump(ZunoDurations.page * 2);
    });
  });

  group('reactions', () {
    Event reactionTo(String target, String id, String sender, String key) =>
        buildTestEvent(
          server.room,
          eventId: id,
          senderId: sender,
          type: EventTypes.Reaction,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reaction,
              'event_id': target,
              'key': key,
            },
          },
        );

    Future<Timeline> timelineOf(List<Event> events) async {
      final db = StoredEventsFakeDatabaseApi()..events = events;
      final loaded = await (buildTestRoom(
        buildTestClient(userId: '@me:example.org', database: db),
      )..partial = false).getTimeline();
      addTearDown(loaded.cancelSubscriptions);
      return loaded;
    }

    Map<String, Object?> rawReaction(String id, String sender, String key) => {
      'event_id': id,
      'type': EventTypes.Reaction,
      'sender': sender,
      'room_id': server.room.id,
      'origin_server_ts': 0,
      'content': {
        'm.relates_to': {
          'rel_type': RelationshipTypes.reaction,
          'event_id': r'$a',
          'key': key,
        },
      },
    };

    http.Response relations(List<Map<String, Object?>> chunk) =>
        http.Response.bytes(
          utf8.encode(jsonEncode({'chunk': chunk})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    testWidgets("an older photo's reactions come from the server", (
      tester,
    ) async {
      server.respond = (request) => request.url.path.contains('/relations/')
          ? relations([rawReaction(r'$r1', '@bob:example.org', '🎉')])
          : null;
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
        chatTimeline: ValueNotifier(await timelineOf([])),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ViewerChrome),
          matching: find.text('🎉'),
        ),
        findsOneWidget,
      );
    });

    testWidgets("reacting while an older photo's reactions still load ends "
        'with what the server has after the reaction', (tester) async {
      final firstAnswer = Completer<void>();
      var relationRequests = 0;
      server.respond = (request) async {
        final path = request.url.path;
        if (path.contains('/relations/')) {
          relationRequests++;
          if (relationRequests == 1) {
            await firstAnswer.future;
            return relations([]);
          }
          return relations([rawReaction(r'$mine', '@me:example.org', '🎉')]);
        }
        if (path.contains('/redact/') || path.contains('/send/')) {
          return http.Response(jsonEncode({'event_id': r'$done'}), 200);
        }
        return null;
      };
      final opened = photo(r'$a', 1);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
        chatTimeline: ValueNotifier(await timelineOf([])),
      );

      await tester.tap(find.byTooltip('React'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('👍'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      firstAnswer.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.descendant(
          of: find.byType(ViewerChrome),
          matching: find.text('🎉'),
        ),
        findsWidgets,
      );
    });

    testWidgets("the shown photo's reactions appear, and the React button "
        'shows mine', (tester) async {
      final opened = photo(r'$a', 1);
      final chatTimeline = ValueNotifier<Timeline?>(
        await timelineOf([
          reactionTo(r'$a', r'$r2', '@me:example.org', '👍'),
          reactionTo(r'$a', r'$r1', '@bob:example.org', '👍'),
          opened,
        ]),
      );
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
        chatTimeline: chatTimeline,
      );

      expect(find.text('2'), findsOneWidget);
      expect(
        find.descendant(of: find.byTooltip('React'), matching: find.text('👍')),
        findsOneWidget,
      );
    });

    testWidgets("new reactions show as the chat's timeline changes", (
      tester,
    ) async {
      final opened = photo(r'$a', 1);
      final chat = ChatTimeline()..value = await timelineOf([opened]);
      addTearDown(chat.dispose);
      await openViewer(
        tester,
        pages: {
          null: (events: [opened], nextBatch: null),
        },
        opened: opened,
        chatTimeline: chat,
      );
      expect(find.text('1'), findsNothing);

      chat.value = await timelineOf([
        reactionTo(r'$a', r'$r1', '@bob:example.org', '🎉'),
        opened,
      ]);
      await tester.pump();

      expect(find.text('🎉'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });
}
