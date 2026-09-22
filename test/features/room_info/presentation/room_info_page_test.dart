import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/optimistic_room_state.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/blocking/presentation/block_person.dart';
import 'package:zuno/features/room_info/presentation/member_tile.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/room_exit.dart';
import 'package:zuno/features/room_info/presentation/room_info_page.dart';
import 'package:zuno/features/room_info/presentation/room_media_page.dart';
import 'package:zuno/features/room_info/presentation/room_media_thumb.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  late List<http.Request> requests;
  var failMembers = false;
  var failPushRules = false;

  setUp(() {
    requests = [];
    failMembers = false;
    failPushRules = false;
    client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (failPushRules && request.url.path.contains('/pushrules/')) {
          return http.Response('{"errcode":"M_UNKNOWN","error":"x"}', 500);
        }
        if (failMembers && request.url.path.endsWith('/members')) {
          return http.Response('{"errcode":"M_UNKNOWN","error":"x"}', 500);
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          for (final id in trustStubbedIds)
            userTrustProvider(id).overrideWithValue(UserTrustState.unconfirmed),
          roomMediaFeedProvider(room)
              .overrideWithValue(mediaFeed ?? mediaFeedOf(const [])),
        ],
        child: MaterialApp(
          home: RoomInfoPage(
            room: room,
            blockPerson: blockPerson,
            onStartCall: onStartCall,
          ),
        ),
      ),
    );
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

  testWidgets('a moderator sees every role', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@ann:example.org', 'Ann');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 50});
    await pumpPage(tester);

    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Moderator'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
  });

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

  testWidgets('Advanced shows for admins and owners only', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 50});
    await pumpPage(tester);
    expect(find.text('Advanced'), findsNothing);

    setLevels({'@owner:example.org': 100, '@me:example.org': 100});
    await pumpPage(tester);
    expect(find.text('Advanced'), findsOneWidget);

    setLevels({'@owner:example.org': 100});
    client.setUserId('@owner:example.org');
    await pumpPage(tester);
    expect(find.text('Advanced'), findsOneWidget);
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

  testWidgets('group rooms have no Security section', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);

    expect(find.text('Security'), findsNothing);
    expect(find.text('Not encrypted'), findsNothing);
  });

  testWidgets('direct chats keep the Security section', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
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
    expect(find.text('Ann blocked'), findsOneWidget);
  });

  testWidgets('a chat offers to block the other person', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 100});
    setDirectChatWith('@owner:example.org');
    final blocked = <String>[];
    await pumpPage(tester, blockPerson: (id) async => blocked.add(id));

    await tester.tap(find.text('Block Olga'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();

    expect(blocked, ['@owner:example.org']);
  });

  testWidgets('backing out of the block dialog blocks nobody', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    setLevels({'@owner:example.org': 100, '@me:example.org': 100});
    setDirectChatWith('@owner:example.org');
    final blocked = <String>[];
    await pumpPage(tester, blockPerson: (id) async => blocked.add(id));

    await tester.tap(find.text('Block Olga'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(blocked, isEmpty);
    expect(find.byType(RoomInfoPage), findsOneWidget);
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

  testWidgets('a room offers no block for the room itself', (tester) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);

    expect(find.textContaining('Block '), findsNothing);
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

  testWidgets('a room has no page-level report, only the member sheet', (
    tester,
  ) async {
    addMember('@owner:example.org', 'Olga');
    addMember('@me:example.org', 'Me');
    await pumpPage(tester);

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

  group('quick actions', () {
    testWidgets('call buttons show only when the chat can start a call', (
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
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
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

    testWidgets('Invite is a quick action in a room that allows it', (
      tester,
    ) async {
      addMember('@me:example.org', 'Me');
      setLevels({'@me:example.org': 100});
      await pumpPage(tester);
      expect(find.text('Invite'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
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
}
