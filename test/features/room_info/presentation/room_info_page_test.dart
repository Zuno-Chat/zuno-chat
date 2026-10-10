import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/optimistic_room_state.dart';
import 'package:zuno/core/matrix/room_exit.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/blocking/presentation/block_person.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/room_info/presentation/member_tile.dart';
import 'package:zuno/features/room_info/presentation/room_info_page.dart';
import 'package:zuno/features/room_info/presentation/room_media_page.dart';
import 'package:zuno/features/room_info/presentation/room_media_thumb.dart';
import 'package:zuno/features/room_info/presentation/room_permissions_page.dart';
import 'package:zuno/features/room_info/presentation/room_settings_page.dart';
import 'package:zuno/features/room_info/presentation/room_topic.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/pump_until.dart';
import '../../../helpers/real_fonts.dart';
import '../../../helpers/room_opening_channels.dart';
import '../../../helpers/route_launcher.dart';

void main() {
  late Client client;
  late Room room;
  late List<http.Request> requests;
  var failMembers = false;
  var failPushRules = false;
  String? refuseRequestsTo;
  Completer<void>? gate;
  RoomInfoResult? pageResult;

  http.Response membersResponse() => http.Response(
    jsonEncode({
      'chunk': [
        for (final member in room.getParticipants())
          {
            'type': EventTypes.RoomMember,
            'event_id': '\$member-${member.id}',
            'room_id': room.id,
            'sender': member.id,
            'state_key': member.id,
            'origin_server_ts': 0,
            'content': member.content,
          },
      ],
    }),
    200,
  );

  setUp(() {
    requests = [];
    failMembers = false;
    failPushRules = false;
    refuseRequestsTo = null;
    gate = null;
    pageResult = null;
    client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        requests.add(request);
        await gate?.future;
        final refusedSegment = refuseRequestsTo;
        if (refusedSegment != null &&
            request.url.pathSegments.contains(refusedSegment)) {
          return http.Response('{"errcode":"M_FORBIDDEN","error":"x"}', 403);
        }
        if (failPushRules && request.url.path.contains('/pushrules/')) {
          return http.Response('{"errcode":"M_UNKNOWN","error":"x"}', 500);
        }
        if (request.url.path.endsWith('/members')) {
          if (failMembers) {
            return http.Response('{"errcode":"M_UNKNOWN","error":"x"}', 500);
          }
          return membersResponse();
        }
        if (request.method == 'PUT' &&
            request.url.pathSegments.contains('state')) {
          return http.Response(jsonEncode({'event_id': r'$state'}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    client.rooms.add(room);
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$create',
        senderId: '@owner:example.org',
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'creator': '@owner:example.org', 'room_version': '10'},
      ),
    );
  });

  void addMember(String id, String name, {String membership = 'join'}) =>
      room.setState(
        User(id, membership: membership, displayName: name, room: room),
      );

  void setLevels(Map<String, int> users) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$powerlevels',
      senderId: '@owner:example.org',
      type: EventTypes.RoomPowerLevels,
      stateKey: '',
      content: {'users': users},
    ),
  );

  void setJoinRule(String rule) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$join',
      senderId: '@owner:example.org',
      type: EventTypes.RoomJoinRules,
      stateKey: '',
      content: {'join_rule': rule},
    ),
  );

  void setDirectChatWith(String userId) =>
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          userId: [room.id],
        },
      );

  void seedCrowd() {
    addMember('@owner:example.org', 'Olga');
    addMember('@ann:example.org', 'Ann');
    addMember('@ben:example.org', 'Ben');
    addMember('@cat:example.org', 'Cat');
    addMember('@dan:example.org', 'Dan');
    addMember('@eve:example.org', 'Eve');
    addMember('@zed:example.org', 'Zed');
  }

  RoomMediaFeed mediaFeedOf(
    List<Event> events, {
    String? nextBatch,
    int pageSize = 40,
  }) {
    final feed = RoomMediaFeed(
      room,
      pageSize: pageSize,
      fetchPage: (_) async => (events: events, nextBatch: nextBatch),
    );
    addTearDown(feed.dispose);
    return feed;
  }

  Event mediaEvent(String id, String msgtype, {String body = 'a'}) =>
      buildTestEvent(
        room,
        eventId: id,
        senderId: '@ann:example.org',
        content: {'msgtype': msgtype, 'body': body, 'url': 'mxc://x/$id'},
        originServerTs: DateTime(2026, 9, 14),
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    List<String> trustStubbedIds = const [],
    RoomMediaFeed? mediaFeed,
    BlockPerson? blockPerson,
    void Function(CallKind kind)? onStartCall,
    int? joinedCount,
    bool pushed = false,
  }) async {
    final members = room.getParticipants();
    room.summary.mJoinedMemberCount =
        joinedCount ??
        members.where((u) => u.membership == Membership.join).length;
    room.summary.mInvitedMemberCount = members
        .where((u) => u.membership == Membership.invite)
        .length;
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = await containerWithPreferences(
      {},
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        for (final id in trustStubbedIds)
          userTrustProvider(id).overrideWithValue(UserTrustState.unconfirmed),
        roomMediaFeedProvider(room)
            .overrideWithValue(mediaFeed ?? mediaFeedOf(const [])),
      ],
    );
    final page = RoomInfoPage(
      room: room,
      blockPerson: blockPerson,
      onStartCall: onStartCall,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: pushed
              ? Scaffold(
                  body: routeLauncher<RoomInfoResult>(
                    (_) => page,
                    onResult: (result) => pageResult = result,
                  ),
                )
              : page,
        ),
      ),
    );
    if (pushed) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Iterable<String> memberIdsIn(Finder scope) =>
      scope.evaluate().map((e) => (e.widget as MemberTile).user.id);

  testWidgets('shows the access under the name', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setJoinRule('public');
    await pumpPage(tester);

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Private'), findsNothing);
  });

  testWidgets(
    'lists the owner first, marked Owner, and hides roles from members',
    (tester) async {
      addMember('@ben:example.org', 'Ben');
      addMember('@owner:example.org', 'Olga');
      addMember('@ann:example.org', 'Ann');
      addMember('@me:example.org', 'Me');
      addMember('@new:example.org', 'New', membership: 'invite');
      setLevels({'@owner:example.org': 100, '@ben:example.org': 50});
      await pumpPage(tester);

      expect(memberIdsIn(find.byType(MemberTile)).first, '@owner:example.org');
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
      expect(find.text('Moderator'), findsNothing);
      expect(find.text('Member'), findsNothing);
    },
  );

  testWidgets('shows five members and a button for the rest', (tester) async {
    seedCrowd();
    await pumpPage(tester);

    expect(find.text('Members (7)'), findsOneWidget);
    expect(find.byType(MemberTile), findsNWidgets(5));
    expect(find.text('Zed'), findsNothing);
    expect(find.text('View all members'), findsOneWidget);
  });

  testWidgets('a small room has no view-all button', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@ann:example.org', 'Ann');
    await pumpPage(tester);

    expect(find.byType(MemberTile), findsNWidgets(2));
    expect(find.text('View all members'), findsNothing);
  });

  testWidgets('view all opens a searchable sheet with everyone', (
    tester,
  ) async {
    seedCrowd();
    await pumpPage(tester);

    await tester.tap(find.text('View all members'));
    await tester.pumpAndSettle();

    final inSheet = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(MemberTile),
    );
    expect(find.text('Members'), findsOneWidget);
    expect(inSheet, findsNWidgets(7));
    expect(memberIdsIn(inSheet).first, '@owner:example.org');

    await tester.enterText(find.byType(TextField), 'zed');
    await tester.pumpAndSettle();

    expect(inSheet, findsOneWidget);
    expect(find.text('Zed'), findsOneWidget);
  });

  testWidgets('reflects room state changes without reopening', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    applyOptimisticRoomState(room, EventTypes.RoomName, {'name': 'Old'});
    await pumpPage(tester);
    expect(find.text('Old'), findsOneWidget);

    applyOptimisticRoomState(room, EventTypes.RoomName, {'name': 'New'});
    await tester.pump();
    await tester.pump();

    expect(find.text('New'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
  });

  testWidgets('shows the topic between the name and the quick actions', (
    tester,
  ) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    applyOptimisticRoomState(room, EventTypes.RoomName, {'name': 'Hikers'});
    applyOptimisticRoomState(room, EventTypes.RoomTopic, {
      'topic': 'Weekend hikes',
    });
    await pumpPage(tester);

    final topicTop = tester.getTopLeft(find.text('Weekend hikes')).dy;
    expect(topicTop, greaterThan(tester.getTopLeft(find.text('Hikers')).dy));
    expect(topicTop, lessThan(tester.getTopLeft(find.text('Mute')).dy));
  });

  testWidgets('a chat shows its topic too', (tester) async {
    addMember('@ann:example.org', 'Ann');
    addMember('@me:example.org', 'Me');
    setDirectChatWith('@ann:example.org');
    applyOptimisticRoomState(room, EventTypes.RoomTopic, {
      'topic': 'Weekend hikes',
    });
    await pumpPage(tester, trustStubbedIds: ['@ann:example.org']);

    expect(find.text('Weekend hikes'), findsOneWidget);
  });

  testWidgets('a blank topic shows nothing', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    applyOptimisticRoomState(room, EventTypes.RoomTopic, {'topic': '  \n '});
    await pumpPage(tester);

    expect(find.byType(RoomTopic), findsNothing);
  });

  testWidgets('shows a changed topic and hides a removed one', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    applyOptimisticRoomState(room, EventTypes.RoomTopic, {'topic': 'Old'});
    await pumpPage(tester);

    applyOptimisticRoomState(room, EventTypes.RoomTopic, {'topic': 'New'});
    await tester.pump();
    await tester.pump();
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Old'), findsNothing);

    applyOptimisticRoomState(room, EventTypes.RoomTopic, {'topic': ''});
    await tester.pump();
    await tester.pump();
    expect(find.byType(RoomTopic), findsNothing);
  });

  testWidgets('separates Encrypted and the access with a bullet', (
    tester,
  ) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$enc',
        senderId: '@owner:example.org',
        type: EventTypes.Encryption,
        stateKey: '',
        content: {'algorithm': 'm.megolm.v1.aes-sha2'},
      ),
    );
    await pumpPage(
      tester,
      trustStubbedIds: ['@owner:example.org', '@me:example.org'],
    );

    expect(find.text('Encrypted'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
  });

  testWidgets('only a direct chat has a Security section', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);
    expect(find.text('Security'), findsNothing);
    expect(find.text('Not encrypted'), findsNothing);

    setDirectChatWith('@owner:example.org');
    await pumpPage(tester);
    expect(find.text('Security'), findsOneWidget);
  });

  testWidgets('direct chats show no Members, and the room ID to admins', (
    tester,
  ) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 100});
    setDirectChatWith('@owner:example.org');
    await pumpPage(tester);

    expect(find.textContaining('Members'), findsNothing);
    expect(find.byType(MemberTile), findsNothing);
    expect(find.text('Room ID'), findsOneWidget);
  });

  testWidgets('direct chats hide the room ID from a non-admin', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 0});
    setDirectChatWith('@owner:example.org');
    await pumpPage(tester);

    expect(find.text('Room ID'), findsNothing);
    expect(find.text('Advanced'), findsNothing);
  });

  testWidgets('media section previews the newest six with counts', (
    tester,
  ) async {
    seedCrowd();
    final feed = mediaFeedOf([
      for (var i = 0; i < 8; i++) mediaEvent('\$img$i', 'm.image'),
      mediaEvent(r'$doc', 'm.file', body: 'notes.txt'),
      mediaEvent(r'$doc2', 'm.file', body: 'more.txt'),
    ]);
    await pumpPage(tester, mediaFeed: feed);

    expect(find.byType(RoomMediaThumb), findsNWidgets(6));
    expect(find.text('More media and files'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Files'), findsNothing);

    await tester.tap(find.text('More media and files'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomMediaPage), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('notes'), findsOneWidget);
  });

  testWidgets('media section marks counts as partial while history remains', (
    tester,
  ) async {
    seedCrowd();
    final feed = mediaFeedOf(
      [for (var i = 0; i < 3; i++) mediaEvent('\$img$i', 'm.image')],
      nextBatch: 'older',
      pageSize: 2,
    );
    await pumpPage(tester, mediaFeed: feed);

    expect(find.text('3+'), findsOneWidget);
  });

  testWidgets('media section says when nothing was shared', (tester) async {
    seedCrowd();
    await pumpPage(tester);

    expect(find.text('No media shared yet.'), findsOneWidget);
    expect(find.byType(RoomMediaThumb), findsNothing);
    expect(find.text('More media and files'), findsNothing);
  });

  testWidgets('media previews sit right above the more row on a phone with a '
      'navigation bar', (tester) async {
    seedCrowd();
    final feed = mediaFeedOf([
      for (var i = 0; i < 3; i++) mediaEvent('\$img$i', 'm.image'),
    ]);
    tester.view.padding = const FakeViewPadding(bottom: 144);
    await pumpPage(tester, mediaFeed: feed);

    final previewsBottom = tester
        .getBottomLeft(find.byType(RoomMediaThumb).first)
        .dy;
    final moreTop = tester
        .getTopLeft(find.widgetWithText(ListTile, 'More media and files'))
        .dy;
    expect(moreTop - previewsBottom, closeTo(8, 0.01));
  });

  Future<void> sendSpamReport(WidgetTester tester) async {
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  http.Request sentReport() =>
      requests.firstWhere((r) => r.url.path.endsWith('/report'));

  testWidgets('any member can report another from the member sheet', (
    tester,
  ) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@ann:example.org', 'Ann');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100});
    await pumpPage(tester);

    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from room'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report Ann'), findsOneWidget);
    await sendSpamReport(tester);

    expect(
      sentReport().url.path,
      '/_matrix/client/v3/users/${Uri.encodeComponent('@ann:example.org')}'
      '/report',
    );
    expect(jsonDecode(sentReport().body), {'reason': 'spam (room ${room.id})'});
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('any member can block another from the member sheet', (
    tester,
  ) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@ann:example.org', 'Ann');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100});
    final blocked = <String>[];
    await pumpPage(tester, blockPerson: (id) async => blocked.add(id));

    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();
    expect(find.text('Ban from room'), findsNothing);
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Block Ann?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();

    expect(blocked, ['@ann:example.org']);
  });

  testWidgets('a chat offers to block the other person, and closes once '
      'they are blocked', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 100});
    setDirectChatWith('@owner:example.org');
    final blocked = <String>[];
    await pumpPage(
      tester,
      blockPerson: (id) async => blocked.add(id),
      pushed: true,
    );

    await tester.tap(find.text('Block Olga'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();

    expect(blocked, ['@owner:example.org']);
    expect(find.byType(RoomInfoPage), findsNothing);
  });

  testWidgets('the official Zuno account cannot be blocked from a chat', (
    tester,
  ) async {
    addMember('@notices:zuno.chat', 'Zuno');
    addMember('@me:example.org', 'Me');
    setDirectChatWith('@notices:zuno.chat');
    await pumpPage(tester);

    expect(find.text('Report Zuno'), findsOneWidget);
    expect(find.text('Block Zuno'), findsNothing);
  });

  testWidgets('the official Zuno account cannot be blocked from a member '
      'sheet', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@notices:zuno.chat', 'Zuno');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100});
    await pumpPage(tester);

    await tester.tap(find.text('Zuno'));
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Block'), findsNothing);
  });

  testWidgets('a chat offers to report the other person', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 100});
    setDirectChatWith('@owner:example.org');
    await pumpPage(tester);

    await tester.tap(find.text('Report Olga'));
    await tester.pumpAndSettle();
    await sendSpamReport(tester);

    expect(
      sentReport().url.path,
      '/_matrix/client/v3/users/${Uri.encodeComponent('@owner:example.org')}'
      '/report',
    );
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('a room offers no page-level block or report, only the member '
      'sheet', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);

    expect(find.textContaining('Block'), findsNothing);
    expect(find.textContaining('Report'), findsNothing);
  });

  testWidgets('closing the report sheet sends nothing', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@ann:example.org', 'Ann');
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);

    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(requests.where((r) => r.url.path.endsWith('/report')), isEmpty);
    expect(find.text('Report sent'), findsNothing);
  });

  testWidgets('people asking to join show to moderators under Asking to '
      'join, never among the members', (tester) async {
    addMember('@me:example.org', 'Me');
    addMember('@ann:example.org', 'Ann');
    addMember('@maya:example.org', 'Maya', membership: 'knock');
    setLevels({'@me:example.org': 50});

    await pumpPage(tester);

    expect(find.text('Asking to join'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Let in'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
  });

  group('quick actions', () {
    testWidgets('the call buttons start a voice or a video call', (
      tester,
    ) async {
      addMember('@me:example.org', 'Me');
      addMember('@ann:example.org', 'Ann');
      final started = <CallKind>[];
      await pumpPage(tester, onStartCall: started.add);

      await tester.tap(find.byTooltip('Voice call'));
      await tester.tap(find.byTooltip('Video call'));
      expect(started, [CallKind.voice, CallKind.video]);
    });

    testWidgets('all four actions fit a small phone at double text size', (
      tester,
    ) async {
      addMember('@me:example.org', 'Me');
      addMember('@ann:example.org', 'Ann');
      await tester.runAsync(loadRealRoboto);
      await pumpPage(tester, onStartCall: (_) {});
      tester.view.physicalSize = const Size(960, 6000);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();

      expect(find.text('Invite'), findsOneWidget);
      expect(find.byTooltip('Voice call'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no call buttons without a way to start one, or alone', (
      tester,
    ) async {
      addMember('@me:example.org', 'Me');
      addMember('@ann:example.org', 'Ann');
      await pumpPage(tester);
      expect(find.byTooltip('Voice call'), findsNothing);

      room.setState(User('@ann:example.org', membership: 'leave', room: room));
      await pumpPage(tester, onStartCall: (_) {});
      expect(find.byTooltip('Voice call'), findsNothing);
    });

    void serverSaysMuted(bool muted) {
      client.accountData['m.push_rules'] = BasicEvent(
        type: 'm.push_rules',
        content: {
          'global': {
            'override': [
              if (muted)
                {
                  'rule_id': room.id,
                  'default': false,
                  'enabled': true,
                  'actions': <Object>[],
                  'conditions': [
                    {
                      'kind': 'event_match',
                      'key': 'room_id',
                      'pattern': room.id,
                    },
                  ],
                },
            ],
          },
        },
      );
      client.onSync.add(
        SyncUpdate(
          nextBatch: 's-${muted ? 'muted' : 'unmuted'}',
          accountData: [client.accountData['m.push_rules']!],
        ),
      );
    }

    Iterable<http.Request> pushRuleWrites() =>
        requests.where((r) => r.url.path.contains('/pushrules/'));

    Future<void> network(WidgetTester tester) async {
      await pumpRealAsync(tester, rounds: 4);
    }

    testWidgets('Mute asks the server once and flips to Unmute', (
      tester,
    ) async {
      addMember('@me:example.org', 'Me');
      await pumpPage(tester);
      expect(find.text('Mute'), findsOneWidget);

      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(find.text('Unmute'), findsOneWidget);

      await tester.tap(find.text('Unmute'));
      await network(tester);
      expect(pushRuleWrites(), hasLength(1));
      expect(pushRuleWrites().single.method, 'PUT');

      serverSaysMuted(true);
      await network(tester);
      expect(find.text('Unmute'), findsOneWidget);
    });

    testWidgets('Unmute works once the mute has arrived from the server', (
      tester,
    ) async {
      addMember('@me:example.org', 'Me');
      await pumpPage(tester);

      await tester.tap(find.text('Mute'));
      await network(tester);
      serverSaysMuted(true);
      await network(tester);

      await tester.tap(find.text('Unmute'));
      await network(tester);

      expect(pushRuleWrites().map((r) => r.method), ['PUT', 'DELETE']);
      expect(find.text('Mute'), findsOneWidget);

      serverSaysMuted(false);
      await network(tester);
      expect(find.text('Mute'), findsOneWidget);
    });

    testWidgets('a refused mute flips back and says so', (tester) async {
      failPushRules = true;
      addMember('@me:example.org', 'Me');
      await pumpPage(tester);

      await tester.tap(find.text('Mute'));
      await network(tester);

      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Not muted. Try again.'), findsOneWidget);
    });
  });

  testWidgets('leaving is offered at the bottom, in the danger color', (
    tester,
  ) async {
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);

    final leave = tester.widget<Text>(find.text(roomExitLabel(room)));
    expect(
      leave.style!.color,
      Theme.of(tester.element(find.byType(RoomInfoPage))).colorScheme.error,
    );
  });

  testWidgets('when the member list cannot be fetched, known members show', (
    tester,
  ) async {
    failMembers = true;
    addMember('@me:example.org', 'Me');
    addMember('@ann:example.org', 'Ann');
    await pumpPage(tester, joinedCount: 5);

    expect(
      requests.where((r) => r.url.path.endsWith('/members')),
      hasLength(1),
    );
    expect(find.byType(MemberTile), findsNWidgets(2));
    expect(find.text('Ann'), findsOneWidget);
  });

  Future<void> network(WidgetTester tester) async {
    await pumpRealAsync(tester, rounds: 4);
    await tester.pumpAndSettle();
  }

  Iterable<http.Request> requestsTo(String segment) =>
      requests.where((r) => r.url.pathSegments.contains(segment));

  Finder memberTile(String userId) =>
      find.byWidgetPredicate((w) => w is MemberTile && w.user.id == userId);

  void seedAdminRoom({int ownLevel = 100, Map<String, int> others = const {}}) {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    addMember('@ann:example.org', 'Ann');
    setLevels({
      '@owner:example.org': 100,
      '@me:example.org': ownLevel,
      ...others,
    });
  }

  Future<void> openMember(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  group('managing a member', () {
    testWidgets('an admin gets every action for a member', (tester) async {
      seedAdminRoom();
      await pumpPage(tester);

      await openMember(tester, 'Ann');

      for (final action in [
        'Start a chat',
        'Change role',
        'Remove from room',
        'Ban from room',
        'Block',
        'Report',
      ]) {
        expect(find.text(action), findsOneWidget, reason: action);
      }
    });

    testWidgets('you, the owner and invitees cannot be managed', (
      tester,
    ) async {
      seedAdminRoom();
      addMember('@new:example.org', 'New', membership: 'invite');
      await pumpPage(tester);

      for (final id in [
        '@me:example.org',
        '@owner:example.org',
        '@new:example.org',
      ]) {
        expect(
          tester.widget<MemberTile>(memberTile(id)).onTap,
          id == '@owner:example.org' ? isNotNull : isNull,
          reason: id,
        );
      }
      await openMember(tester, 'Olga');
      expect(find.text('Change role'), findsNothing);
      expect(find.text('Remove from room'), findsNothing);
      expect(find.text('Start a chat'), findsOneWidget);
    });

    testWidgets('an admin changes a role and it shows at once', (tester) async {
      seedAdminRoom();
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Member').last,
          matching: find.byIcon(Icons.check_outlined),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Moderator').last);
      await network(tester);

      final sent =
          jsonDecode(requestsTo('m.room.power_levels').single.body) as Map;
      expect((sent['users'] as Map)['@ann:example.org'], 50);
      expect(
        find.descendant(
          of: memberTile('@ann:example.org'),
          matching: find.text('Moderator'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeping the same role sends nothing', (tester) async {
      seedAdminRoom();
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member').last);
      await network(tester);

      expect(requestsTo('m.room.power_levels'), isEmpty);
    });

    testWidgets('a refused role change says so', (tester) async {
      seedAdminRoom();
      refuseRequestsTo = 'm.room.power_levels';
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await network(tester);

      expect(find.text('Role not changed. Try again.'), findsOneWidget);
    });

    testWidgets('removing asks first, then takes them off the list', (
      tester,
    ) async {
      seedAdminRoom();
      await pumpPage(tester);
      expect(find.text('Members (3)'), findsOneWidget);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Remove from room'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Ann?'), findsOneWidget);
      expect(
        find.text(
          'They are removed from the room and can rejoin if invited again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await network(tester);

      expect(jsonDecode(requestsTo('kick').single.body), {
        'user_id': '@ann:example.org',
      });
      expect(memberTile('@ann:example.org'), findsNothing);
      expect(find.text('Members (2)'), findsOneWidget);
    });

    testWidgets('backing out of removal removes nobody', (tester) async {
      seedAdminRoom();
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Remove from room'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await network(tester);

      expect(requestsTo('kick'), isEmpty);
      expect(memberTile('@ann:example.org'), findsOneWidget);
    });

    testWidgets('a refused removal keeps them and says so', (tester) async {
      seedAdminRoom();
      refuseRequestsTo = 'kick';
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Remove from room'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await network(tester);

      expect(find.text('Not removed. Try again.'), findsOneWidget);
      expect(memberTile('@ann:example.org'), findsOneWidget);
    });

    testWidgets('banning moves them to Banned, and Unban clears it', (
      tester,
    ) async {
      seedAdminRoom();
      await pumpPage(tester);
      expect(find.text('Banned'), findsNothing);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Ban from room'));
      await tester.pumpAndSettle();
      expect(find.text('Ban Ann?'), findsOneWidget);
      expect(
        find.text(
          'They are removed from the room and cannot rejoin unless unbanned.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Ban'));
      await network(tester);

      expect(requestsTo('ban'), hasLength(1));
      expect(memberTile('@ann:example.org'), findsNothing);
      expect(find.text('Banned'), findsOneWidget);
      expect(find.text('@ann'), findsOneWidget);

      await tester.tap(find.text('Unban'));
      await network(tester);

      expect(jsonDecode(requestsTo('unban').single.body), {
        'user_id': '@ann:example.org',
      });
      expect(find.text('Banned'), findsNothing);
    });

    testWidgets('a refused ban says so', (tester) async {
      seedAdminRoom();
      refuseRequestsTo = 'ban';
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Ban from room'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Ban'));
      await network(tester);

      expect(find.text('Not banned. Try again.'), findsOneWidget);
      expect(find.text('Banned'), findsNothing);
    });

    testWidgets('a refused unban keeps them banned and says so', (
      tester,
    ) async {
      seedAdminRoom();
      addMember('@bad:example.org', 'Bad', membership: 'ban');
      refuseRequestsTo = 'unban';
      await pumpPage(tester);

      await tester.tap(find.text('Unban'));
      await network(tester);

      expect(find.text('Not unbanned. Try again.'), findsOneWidget);
      expect(find.text('Bad'), findsOneWidget);
    });

    testWidgets('only someone of lower rank can be unbanned', (tester) async {
      seedAdminRoom(ownLevel: 50, others: {'@bad:example.org': 50});
      addMember('@bad:example.org', 'Bad', membership: 'ban');
      await pumpPage(tester);

      expect(find.text('Banned'), findsOneWidget);
      expect(find.text('Bad'), findsOneWidget);
      expect(find.text('Unban'), findsNothing);
    });

    testWidgets('members cannot see who is banned', (tester) async {
      seedAdminRoom(ownLevel: 0);
      addMember('@bad:example.org', 'Bad', membership: 'ban');
      await pumpPage(tester);

      expect(find.text('Banned'), findsNothing);
    });

    testWidgets('someone picked from the full list gets the same actions', (
      tester,
    ) async {
      seedCrowd();
      addMember('@me:example.org', 'Me');
      setLevels({'@owner:example.org': 100, '@me:example.org': 100});
      await pumpPage(tester);

      await tester.tap(find.text('View all members'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zed'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from room'), findsOneWidget);
    });

    testWidgets('closing the full list manages nobody', (tester) async {
      seedCrowd();
      await pumpPage(tester);

      await tester.tap(find.text('View all members'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Start a chat'), findsNothing);
    });

    testWidgets('Start a chat opens the chat you already have with them', (
      tester,
    ) async {
      installRoomOpeningChannels();
      seedAdminRoom();
      final chat = buildTestRoom(client, id: '!ann:example.org')
        ..partial = false;
      client.rooms.add(chat);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@ann:example.org': [chat.id],
        },
      );
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Start a chat'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(requestsTo('createRoom'), isEmpty);
      final page = tester.widget<RoomPage>(find.byType(RoomPage));
      expect(page.room, chat);
    });

    testWidgets('a chat that cannot be started says so', (tester) async {
      seedAdminRoom();
      refuseRequestsTo = 'createRoom';
      await pumpPage(tester);

      await openMember(tester, 'Ann');
      await tester.tap(find.text('Start a chat'));
      await network(tester);

      expect(requestsTo('createRoom'), hasLength(1));
      expect(find.text('Could not start the chat. Try again.'), findsOneWidget);
    });
  });

  group('inviting', () {
    Future<void> invite(WidgetTester tester, String username) async {
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.text('Invite to room'), findsOneWidget);
      await tester.enterText(find.byType(TextField), username);
      await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    }

    testWidgets('sends the invitation and lists them as invited', (
      tester,
    ) async {
      seedAdminRoom();
      await pumpPage(tester);

      await invite(tester, 'bob');
      await network(tester);

      expect(jsonDecode(requestsTo('invite').single.body), {
        'user_id': '@bob:example.org',
      });
      expect(find.text('Invitation sent'), findsOneWidget);
      expect(
        find.descendant(
          of: memberTile('@bob:example.org'),
          matching: find.text('Invited'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a refused invitation says so', (tester) async {
      seedAdminRoom();
      refuseRequestsTo = 'invite';
      await pumpPage(tester);

      await invite(tester, 'bob');
      await network(tester);

      expect(find.text('Invitation not sent. Try again.'), findsOneWidget);
      expect(memberTile('@bob:example.org'), findsNothing);
    });

    testWidgets('cancelling sends nothing', (tester) async {
      seedAdminRoom();
      await pumpPage(tester);

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await network(tester);

      expect(requestsTo('invite'), isEmpty);
    });

    testWidgets('an invitation that lands after the page closed still counts '
        'as sent', (tester) async {
      seedAdminRoom();
      await pumpPage(tester, pushed: true);

      gate = Completer<void>();
      await invite(tester, 'bob');
      await tester.pump();
      Navigator.of(tester.element(find.byType(RoomInfoPage))).pop();
      await tester.pumpAndSettle();
      gate!.complete();
      await network(tester);

      expect(find.text('Invitation sent'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.text('open')))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('encryption in a chat', () {
    void seedPlainChat({int ownLevel = 100}) {
      addMember('@owner:example.org', 'Olga');
      addMember('@me:example.org', 'Me');
      setLevels({'@owner:example.org': 100, '@me:example.org': ownLevel});
      setDirectChatWith('@owner:example.org');
    }

    Future<void> enable(WidgetTester tester) async {
      await tester.tap(find.text('Enable encryption'));
      await tester.pumpAndSettle();
      expect(find.text('Enable encryption?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Enable encryption'));
      await network(tester);
    }

    testWidgets('can be turned on after a warning, and shows at once', (
      tester,
    ) async {
      seedPlainChat();
      await pumpPage(tester, trustStubbedIds: ['@owner:example.org']);
      expect(find.text('Not encrypted'), findsOneWidget);

      await enable(tester);

      expect(jsonDecode(requestsTo('m.room.encryption').single.body), {
        'algorithm': 'm.megolm.v1.aes-sha2',
      });
      expect(find.text('Not encrypted'), findsNothing);
      expect(find.text('Enable encryption'), findsNothing);
      expect(find.text('Encrypted'), findsOneWidget);
    });

    testWidgets('cancelling leaves it off', (tester) async {
      seedPlainChat();
      await pumpPage(tester);

      await tester.tap(find.text('Enable encryption'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await network(tester);

      expect(requestsTo('m.room.encryption'), isEmpty);
      expect(find.text('Not encrypted'), findsOneWidget);
    });

    testWidgets('a refusal says so', (tester) async {
      seedPlainChat();
      refuseRequestsTo = 'm.room.encryption';
      await pumpPage(tester);

      await enable(tester);

      expect(find.text('Encryption not enabled. Try again.'), findsOneWidget);
      expect(find.text('Not encrypted'), findsOneWidget);
    });

    testWidgets('someone who may not change it is only told', (tester) async {
      seedPlainChat(ownLevel: 0);
      await pumpPage(tester);

      expect(find.text('Not encrypted'), findsOneWidget);
      expect(find.text('Enable encryption'), findsNothing);
    });

    testWidgets('an encrypted chat offers to confirm the other person', (
      tester,
    ) async {
      seedPlainChat();
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$enc',
          senderId: '@owner:example.org',
          type: EventTypes.Encryption,
          stateKey: '',
          content: {'algorithm': 'm.megolm.v1.aes-sha2'},
        ),
      );
      await pumpPage(tester, trustStubbedIds: ['@owner:example.org']);

      expect(find.text('Not encrypted'), findsNothing);
      expect(find.text('Confirm it is really @owner'), findsOneWidget);
    });
  });

  group('room pages', () {
    testWidgets('an admin opens the room settings', (tester) async {
      seedAdminRoom();
      await pumpPage(tester);

      await tester.tap(find.text('Room settings'));
      await tester.pumpAndSettle();

      expect(find.byType(RoomSettingsPage), findsOneWidget);
    });

    testWidgets('an admin opens roles and permissions to edit them', (
      tester,
    ) async {
      seedAdminRoom();
      await pumpPage(tester);
      expect(find.text('Who can do what'), findsOneWidget);

      await tester.tap(find.text('Roles & permissions'));
      await tester.pumpAndSettle();

      expect(find.byType(RoomPermissionsPage), findsOneWidget);
    });

    testWidgets('a moderator may only view roles and permissions', (
      tester,
    ) async {
      seedAdminRoom(ownLevel: 50);
      await pumpPage(tester);

      expect(find.text('View only'), findsOneWidget);
    });

    testWidgets('a member sees neither', (tester) async {
      seedAdminRoom(ownLevel: 0);
      await pumpPage(tester);

      expect(find.text('Room settings'), findsNothing);
      expect(find.text('Roles & permissions'), findsNothing);
    });
  });

  group('leaving', () {
    testWidgets('closes the page and says the room was left', (tester) async {
      seedAdminRoom();
      await pumpPage(tester, pushed: true);

      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await network(tester);

      expect(requestsTo('leave'), hasLength(1));
      expect(find.byType(RoomInfoPage), findsNothing);
      expect(pageResult, RoomInfoResult.left);
    });

    testWidgets('backing out keeps the page open', (tester) async {
      seedAdminRoom();
      await pumpPage(tester, pushed: true);

      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await network(tester);

      expect(requestsTo('leave'), isEmpty);
      expect(find.byType(RoomInfoPage), findsOneWidget);
    });
  });

  testWidgets('an admin can copy the room ID and address', (tester) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    seedAdminRoom();
    applyOptimisticRoomState(room, EventTypes.RoomCanonicalAlias, {
      'alias': '#chess:example.org',
    });
    await pumpPage(tester);

    await tester.tap(find.text('Room ID'));
    await tester.pump();
    expect(find.text('Room ID copied'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(RoomInfoPage)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Room alias'));
    await tester.pump();
    expect(find.text('Room alias copied'), findsOneWidget);

    expect(copied, ['!room', '#chess']);
  });

  testWidgets('a room without an address offers only its ID to copy', (
    tester,
  ) async {
    seedAdminRoom();
    await pumpPage(tester);

    expect(find.text('Room ID'), findsOneWidget);
    expect(find.text('Room alias'), findsNothing);
  });

  testWidgets('pulling down fetches the members again', (tester) async {
    addMember('@me:example.org', 'Me');
    addMember('@ann:example.org', 'Ann');
    await pumpPage(tester, joinedCount: 5);
    expect(requestsTo('members'), hasLength(1));

    await tester.fling(find.text('Members (2)'), const Offset(0, 800), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await network(tester);

    expect(requestsTo('members'), hasLength(2));
  });
}
