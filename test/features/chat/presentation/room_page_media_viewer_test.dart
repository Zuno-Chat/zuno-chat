import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/features/chat/presentation/media_viewer/media_viewer_page.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_chrome.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/room_info/presentation/room_info_page.dart';
import 'package:zuno/features/room_info/presentation/room_media_thumb.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;

  setUp(() => recordChannel(SystemChannels.platform));

  Event photo(String id, int minute, {Map<String, Object?> extra = const {}}) =>
      buildTestEvent(
        harness.room,
        eventId: id,
        senderId: '@bob:example.org',
        originServerTs: DateTime(2026, 9, 20, 12, minute),
        status: EventStatus.synced,
        content: {
          'msgtype': MessageTypes.Image,
          'body': '${id.substring(1)}.jpg',
          'url': 'mxc://example.org/${id.substring(1)}',
          'info': {'w': 400, 'h': 300, 'mimetype': 'image/jpeg'},
          ...extra,
        },
      );

  List<Event> gallery() => [
    for (final index in [2, 1, 0])
      photo(
        '\$g$index',
        10 + index,
        extra: galleryGroupContent(id: 'g', index: index, count: 3),
      ),
  ];

  Future<void> openRoom(
    WidgetTester tester,
    List<Event> Function() events, {
    bool viaLauncher = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      overrides: [
        roomMediaFeedProvider.overrideWith(
          (ref, room) => RoomMediaFeed(
            room,
            fetchPage: (_) async => (events: events(), nextBatch: null),
          ),
        ),
      ],
    );
    harness.room.summary.mJoinedMemberCount = 2;
    harness.respond = (request) {
      final path = request.url.path;
      if (path.contains('/send/m.reaction/')) {
        return http.Response(jsonEncode({'event_id': r'$reacted'}), 200);
      }
      if (path.contains('/media/') && path.contains('/download/')) {
        return http.Response(
          jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
          404,
        );
      }
      return null;
    };
    harness.db.events = events();
    if (viaLauncher) {
      await harness.pumpRoomPageOverLauncher(tester);
    } else {
      await harness.pumpRoomPage(tester);
    }
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await harness.settle(tester);
    await tester.pump();
    await tester.pump(ZunoDurations.page * 2);
  }

  Future<void> openFirstGalleryPhoto(WidgetTester tester) async {
    await tapAndSettle(
      tester,
      find
          .descendant(
            of: find.byType(GalleryMessage),
            matching: find.byType(AspectRatio),
          )
          .first,
    );
  }

  String shown(WidgetTester tester) =>
      tester.widget<ViewerChrome>(find.byType(ViewerChrome)).event.eventId;

  Iterable<http.Request> requestsTo(String part) =>
      harness.httpRequests.where((r) => r.url.path.contains(part));

  testWidgets('tapping a photo opens the viewer on it', (tester) async {
    await openRoom(tester, () => [photo(r'$p', 1)]);

    await tapAndSettle(tester, find.byType(ImageMessage));

    expect(find.byType(MediaViewerPage), findsOneWidget);
    expect(shown(tester), r'$p');
  });

  testWidgets('Reply in the viewer returns to the chat with the reply '
      'started', (tester) async {
    await openRoom(tester, () => [photo(r'$p', 1)]);
    await tapAndSettle(tester, find.byType(ImageMessage));

    await tapAndSettle(tester, find.byTooltip('Reply'));

    expect(find.byType(MediaViewerPage), findsNothing);
    expect(find.text('Replying to Bob'), findsOneWidget);
  });

  testWidgets('React on a gallery photo reacts to the gallery message', (
    tester,
  ) async {
    await openRoom(tester, gallery);
    await openFirstGalleryPhoto(tester);
    expect(shown(tester), r'$g0');

    await tester.tap(find.byTooltip('React'));
    await harness.settle(tester);
    await tester.tap(find.text('👍'));
    await harness.settle(tester);

    final reaction = requestsTo('/send/m.reaction/').single;
    final relates = (jsonDecode(reaction.body) as Map)['m.relates_to'] as Map;
    expect((relates['event_id'], relates['key']), (r'$g2', '👍'));
  });

  testWidgets('More on a gallery photo opens the gallery sheet', (
    tester,
  ) async {
    await openRoom(tester, gallery);
    await openFirstGalleryPhoto(tester);

    await tester.tap(find.byTooltip('More'));
    await harness.settle(tester);

    expect(find.text('Save all (3)'), findsOneWidget);
  });

  testWidgets('Reply from the viewer over Media closes the viewer and room '
      'info', (tester) async {
    await openRoom(tester, () => [photo(r'$p', 1)], viaLauncher: true);
    await harness.openRoomInfo(tester);
    expect(find.byType(RoomInfoPage), findsOneWidget);

    await tapAndSettle(tester, find.byType(RoomMediaThumb).first);
    expect(shown(tester), r'$p');

    await tapAndSettle(tester, find.byTooltip('Reply'));

    expect(find.byType(MediaViewerPage), findsNothing);
    expect(find.byType(RoomInfoPage), findsNothing);
    expect(find.byType(RoomPage), findsOneWidget);
    expect(find.text('Replying to Bob'), findsOneWidget);
  });

  testWidgets('the photo stays in its bubble behind the viewer', (
    tester,
  ) async {
    await openRoom(tester, () => [photo(r'$p', 1)]);
    await tapAndSettle(tester, find.byType(ImageMessage));

    expect(
      find.descendant(
        of: find.byType(ImageMessage, skipOffstage: false),
        matching: find.byType(Image, skipOffstage: false),
      ),
      findsWidgets,
    );
  });

  testWidgets('the chat and room info tag their photos apart, so opening room '
      'info flies nothing', (tester) async {
    await openRoom(tester, () => [photo(r'$p', 1)], viaLauncher: true);
    await harness.openRoomInfo(tester);

    final tags = {
      for (final hero in tester.widgetList<Hero>(
        find.byType(Hero, skipOffstage: false),
      ))
        if (hero.tag case (final Route<dynamic> _, final String id)
            when id == r'$p')
          hero.tag,
    };
    expect(tags, hasLength(2));
  });

  testWidgets("a gallery photo shows the gallery's reactions, and tapping one "
      'reacts to the gallery message', (tester) async {
    await openRoom(
      tester,
      () => [
        buildTestEvent(
          harness.room,
          eventId: r'$liked',
          senderId: '@bob:example.org',
          originServerTs: DateTime(2026, 9, 20, 12, 20),
          type: EventTypes.Reaction,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reaction,
              'event_id': r'$g2',
              'key': '🎉',
            },
          },
        ),
        ...gallery(),
      ],
    );
    await openFirstGalleryPhoto(tester);
    expect(shown(tester), r'$g0');

    await tester.tap(
      find.descendant(of: find.byType(ViewerChrome), matching: find.text('🎉')),
    );
    await harness.settle(tester);

    final reaction = requestsTo('/send/m.reaction/').single;
    final relates = (jsonDecode(reaction.body) as Map)['m.relates_to'] as Map;
    expect((relates['event_id'], relates['key']), (r'$g2', '🎉'));
  });
}
