import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/communities/presentation/community_page.dart';
import 'package:zuno/features/rooms/presentation/chat_row.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/layout_matrix.dart';

const _me = '@me:example.org';

class _StoredStateDatabase extends TimelineCapableFakeDatabaseApi {
  List<Event> states = [];

  @override
  Future<List<Event>> getUnimportantRoomEventStatesForRoom(
    List<String> events,
    Room room,
  ) async => states;
}

void main() {
  late Client client;
  late _StoredStateDatabase stored;
  late Room club;
  late List<http.Request> requests;
  late Completer<List<SpaceRoomsChunk$2>> more;
  late int loads;
  late bool offline;
  bool Function(String path)? refuse;
  Room? opened;

  void putState(
    Room room,
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
  }) {
    room.setState(
      buildTestEvent(
        room,
        eventId: '\$$type-${room.id}-$stateKey',
        senderId: _me,
        type: type,
        stateKey: stateKey,
        content: content,
        originServerTs: DateTime(2026),
      ),
    );
  }

  Room member(String id, String name) {
    final room = buildTestRoom(client, id: id)..membership = Membership.join;
    putState(room, EventTypes.RoomName, {'name': name});
    putState(room, EventTypes.Encryption, {
      'algorithm': 'm.megolm.v1.aes-sha2',
    });
    room.lastEvent = buildTestEvent(
      room,
      eventId: '\$msg-$id',
      senderId: '@maya:example.org',
      content: {'msgtype': 'm.text', 'body': 'Spare shoes in 41'},
      originServerTs: DateTime.now(),
    );
    client.rooms.add(room);
    putState(club, EventTypes.SpaceChild, {
      'via': ['example.org'],
    }, stateKey: id);
    return room;
  }

  void makeAdmin() => putState(club, EventTypes.RoomPowerLevels, {
    'users': {_me: 100},
    'events_default': 100,
    'state_default': 100,
    'events': {EventTypes.SpaceChild: 50},
  });

  SpaceRoomsChunk$2 chunk(
    String id,
    String name, {
    int members = 8,
    String? joinRule,
  }) => SpaceRoomsChunk$2.fromJson({
    'room_id': id,
    'name': name,
    'topic': 'Start here if you are new',
    'num_joined_members': members,
    'guest_can_join': false,
    'world_readable': false,
    'children_state': <Object>[],
    'join_rule': ?joinRule,
  });

  Future<List<Override>> overrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return [
      matrixClientProvider.overrideWithValue(client),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ];
  }

  setUp(() {
    requests = [];
    loads = 0;
    opened = null;
    offline = false;
    refuse = null;
    stored = _StoredStateDatabase();
    client = buildTestClient(
      userId: _me,
      database: stored,
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = Uri.decodeComponent(request.url.path);
        if (offline) {
          throw http.ClientException('Failed host lookup', request.url);
        }
        if (refuse?.call(path) ?? false) {
          return http.Response(
            jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
            403,
          );
        }
        if (path.endsWith('/members')) {
          return http.Response(
            jsonEncode({
              'chunk': [
                for (final user in club.getParticipants())
                  {
                    'type': EventTypes.RoomMember,
                    'state_key': user.id,
                    'sender': user.id,
                    'event_id': '\$member-${user.id}',
                    'origin_server_ts': 0,
                    'content': {
                      'membership': user.membership.name,
                      'displayname': ?user.displayName,
                    },
                  },
              ],
            }),
            200,
          );
        }
        if (path.contains('/knock/')) {
          return http.Response(
            jsonEncode({'room_id': path.split('/').last}),
            200,
          );
        }
        if (path.contains('/join/')) {
          final id = path.split('/join/').last;
          client.getRoomById(id)?.membership = Membership.join;
          return http.Response(jsonEncode({'room_id': id}), 200);
        }
        if (path.endsWith('/createRoom')) {
          return http.Response(
            jsonEncode({'room_id': '!new:example.org'}),
            200,
          );
        }
        if (path.contains('/state/')) {
          return http.Response(jsonEncode({'event_id': r'$state'}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    club = buildTestRoom(client, id: '!club:example.org')
      ..membership = Membership.join;
    putState(club, EventTypes.RoomCreate, {'type': 'm.space'});
    putState(club, EventTypes.RoomName, {'name': 'Climbing club'});
    putState(club, EventTypes.RoomTopic, {'topic': 'Bouldering on Saturdays'});
    putState(club, EventTypes.RoomJoinRules, {'join_rule': 'invite'});
    putState(club, EventTypes.RoomPowerLevels, {
      'users': {_me: 0},
      'events_default': 100,
      'state_default': 100,
      'invite': 0,
      'events': {EventTypes.SpaceChild: 50},
    });
    club.summary.mJoinedMemberCount = 24;
    client.rooms.add(club);
  });

  Future<void> pump(WidgetTester tester) async {
    more = Completer();
    final scope = await overrides();
    await tester.pumpWidget(
      ProviderScope(
        overrides: scope,
        child: MaterialApp(
          theme: zunoLightTheme,
          home: CommunityPage(
            community: club,
            loadRooms: (_) {
              loads++;
              return more.future;
            },
            openRoom: (_, room) => opened = room,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the community, its members and access, and the rooms '
      'you are in', (tester) async {
    member('!gear:example.org', 'Gear swap');

    await pump(tester);

    expect(find.text('Climbing club'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('24 members'), findsOneWidget);
    expect(find.text('Bouldering on Saturdays'), findsOneWidget);
    expect(find.text('Your rooms'), findsOneWidget);
    expect(find.text('Gear swap'), findsOneWidget);
    expect(find.byType(ChatRow), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('after a cold start, the rest of the community is read from '
      'this device', (tester) async {
    final topic = club.getState(EventTypes.RoomTopic)! as Event;
    club.states.remove(EventTypes.RoomTopic);
    makeAdmin();
    final levels = club.getState(EventTypes.RoomPowerLevels)! as Event;
    club.states.remove(EventTypes.RoomPowerLevels);
    club.partial = true;
    stored.states = [topic, levels];

    await pump(tester);
    await tester.pump();

    expect(club.partial, isFalse);
    expect(find.text('Bouldering on Saturdays'), findsOneWidget);
    expect(find.text('New room'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('rooms you can join load once the page opens, without the ones '
      'you are in', (tester) async {
    member('!gear:example.org', 'Gear swap');
    await pump(tester);

    more.complete([
      chunk('!gear:example.org', 'Gear swap'),
      chunk('!beginners:example.org', 'Beginners'),
    ]);
    await tester.pump();

    expect(loads, 1);
    expect(find.text('More rooms'), findsOneWidget);
    expect(find.text('Beginners'), findsOneWidget);
    expect(find.text('8 members • Start here if you are new'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
  });

  testWidgets('joining a room joins it through the servers the community lists '
      'and opens it', (tester) async {
    putState(club, EventTypes.SpaceChild, {
      'via': ['other.example'],
    }, stateKey: '!beginners:example.org');
    await pump(tester);
    final beginners = buildTestRoom(client, id: '!beginners:example.org')
      ..membership = Membership.invite;
    client.rooms.add(beginners);
    more.complete([chunk(beginners.id, 'Beginners')]);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    final join = requests.firstWhere(
      (r) => Uri.decodeComponent(r.url.path).contains('/join/'),
    );
    expect(
      Uri.decodeComponent(join.url.path),
      '/_matrix/client/v3/join/!beginners:example.org',
    );
    expect(join.url.queryParametersAll['via'], ['other.example']);
    expect(opened, beginners);
  });

  testWidgets('tapping a room you are in opens it', (tester) async {
    final gear = member('!gear:example.org', 'Gear swap');
    await pump(tester);

    await tester.tap(find.text('Gear swap'));

    expect(opened, gear);
  });

  testWidgets('rooms that fail to load say so and try again', (tester) async {
    await pump(tester);
    more.completeError(Exception('offline'));
    await tester.pump();

    expect(find.text('Could not load more rooms.'), findsOneWidget);

    more = Completer();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    more.complete([chunk('!trips:example.org', 'Trips')]);
    await tester.pump();

    expect(loads, 2);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Could not load more rooms.'), findsNothing);
  });

  testWidgets('a community with no rooms says so', (tester) async {
    await pump(tester);
    more.complete(const []);
    await tester.pump();

    expect(find.text('No rooms here yet'), findsOneWidget);
    expect(find.text('Your rooms'), findsNothing);
    expect(find.text('More rooms'), findsNothing);
  });

  testWidgets('a member can invite but not add rooms or change settings', (
    tester,
  ) async {
    await pump(tester);
    more.complete(const []);

    expect(find.text('Invite'), findsOneWidget);
    expect(find.text('New room'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Community settings'), findsNothing);
    expect(find.text('Roles & permissions'), findsNothing);
    expect(find.text('Leave community'), findsOneWidget);
  });

  testWidgets('an admin can add rooms and change settings', (tester) async {
    makeAdmin();
    await pump(tester);
    more.complete(const []);

    expect(find.text('New room'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Community settings'), findsOneWidget);
  });

  testWidgets('a new room is open to the community and opens once made', (
    tester,
  ) async {
    makeAdmin();
    await pump(tester);
    more.complete(const []);
    final created = buildTestRoom(client, id: '!new:example.org')
      ..membership = Membership.join;

    await tester.tap(find.text('New room'));
    await tester.pumpAndSettle();
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );
    expect(inDialog('Anyone in Climbing club can join'), findsOneWidget);
    expect(inDialog('Ask to join'), findsOneWidget);
    expect(inDialog('Private'), findsOneWidget);
    expect(inDialog('Public'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Gear swap');
    client.rooms.add(created);
    await tester.tap(find.text('Create'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }

    expect(
      requests.map((r) => r.url.path),
      contains('/_matrix/client/v3/createRoom'),
    );
    expect(opened?.id, created.id);
  });

  testWidgets('a room made to ask for joining is created that way', (
    tester,
  ) async {
    makeAdmin();
    await pump(tester);
    more.complete(const []);
    client.rooms.add(
      buildTestRoom(client, id: '!new:example.org')
        ..membership = Membership.join,
    );

    await tester.tap(find.text('New room'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Coaches');
    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }

    final create = requests.firstWhere(
      (r) => r.url.path.endsWith('/createRoom'),
    );
    final initial = (jsonDecode(create.body) as Map)['initial_state'] as List;
    expect(
      initial.firstWhere(
        (state) => (state as Map)['type'] == EventTypes.RoomJoinRules,
      )['content'],
      {'join_rule': 'knock'},
    );
  });

  testWidgets('being removed from the community closes its page', (
    tester,
  ) async {
    final scope = await overrides();
    await tester.pumpWidget(
      ProviderScope(
        overrides: scope,
        child: MaterialApp(
          theme: zunoLightTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CommunityPage(
                    community: club,
                    loadRooms: (_) async => const [],
                    openRoom: (_, _) {},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPage), findsOneWidget);

    client.onSync.add(
      SyncUpdate(
        nextBatch: 'unrelated',
        rooms: RoomsUpdate(
          join: {'!elsewhere:example.org': JoinedRoomUpdate()},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPage), findsOneWidget);

    club.membership = Membership.leave;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'removed',
        rooms: RoomsUpdate(leave: {club.id: LeftRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CommunityPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('what can go wrong', () {
    Future<void> network(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('a join that fails says so and keeps the room offered', (
      tester,
    ) async {
      await pump(tester);
      more.complete([chunk('!trips:example.org', 'Trips')]);
      await tester.pump();
      offline = true;

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await network(tester);

      expect(
        find.text(
          'Could not join the room. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
    });

    testWidgets('a request that cannot be sent says so', (tester) async {
      await pump(tester);
      more.complete([
        chunk('!coaches:example.org', 'Coaches', joinRule: 'knock'),
      ]);
      await tester.pump();
      offline = true;

      await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
      await network(tester);

      expect(
        find.text(
          'Could not send the request. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Ask'), findsOneWidget);
    });

    testWidgets('a room made while the community refuses it is still opened '
        'and the gap named', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      client.rooms.add(
        buildTestRoom(client, id: '!new:example.org')
          ..membership = Membership.join,
      );
      refuse = (path) => path.contains('/state/');

      await tester.tap(find.text('New room'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gear swap');
      await tester.tap(find.text('Create'));
      await network(tester);

      expect(
        find.text('Room created, but not added to Climbing club.'),
        findsOneWidget,
      );
      expect(opened?.id, '!new:example.org');
    });

    testWidgets('a room that cannot be made says so', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      offline = true;

      await tester.tap(find.text('New room'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gear swap');
      await tester.tap(find.text('Create'));
      await network(tester);

      expect(
        find.text(
          'Could not create the room. Check your connection and try '
          'again.',
        ),
        findsOneWidget,
      );
      expect(opened, isNull);
    });
  });

  group('inviting', () {
    Future<void> invite(WidgetTester tester) async {
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sam');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Invite'),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    testWidgets('sends the invitation to someone on this server', (
      tester,
    ) async {
      await pump(tester);
      more.complete(const []);

      await invite(tester);

      final sent = requests.lastWhere((r) => r.url.path.endsWith('/invite'));
      expect(jsonDecode(sent.body), {'user_id': '@sam:example.org'});
      expect(find.text('Invitation sent'), findsOneWidget);
    });

    testWidgets('an invitation that fails says so', (tester) async {
      await pump(tester);
      more.complete(const []);
      offline = true;

      await invite(tester);

      expect(find.text('Invitation not sent. Try again.'), findsOneWidget);
    });
  });

  testWidgets('news in one of its rooms shows at once', (tester) async {
    final gear = member('!gear:example.org', 'Gear swap');
    await pump(tester);
    more.complete(const []);

    gear.lastEvent = buildTestEvent(
      gear,
      eventId: r'$newer',
      senderId: '@leo:example.org',
      content: {'msgtype': 'm.text', 'body': 'Chalk bags on sale'},
      originServerTs: DateTime.now(),
    );
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'news',
        rooms: RoomsUpdate(join: {gear.id: JoinedRoomUpdate()}),
      ),
    );
    await tester.pump();

    expect(find.text('Chalk bags on sale'), findsOneWidget);
  });

  testWidgets('a room you are in opens in the chat by default', (tester) async {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      MethodChannel('dexterous.com/flutter/local_notifications'),
      MethodChannel('zuno/calls'),
      MethodChannel('com.llfbandit.record/messages'),
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'initialize' ? true : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    final gear = member('!gear:example.org', 'Gear swap')..partial = false;
    final container = ProviderContainer(overrides: await overrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: zunoLightTheme,
          home: CommunityPage(
            community: club,
            loadRooms: (_) async => const [],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Gear swap'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.widget<RoomPage>(find.byType(RoomPage)).room, gear);
  });

  group('rooms that ask for joining', () {
    testWidgets('offer Ask, which sends the request and shows Requested', (
      tester,
    ) async {
      await pump(tester);
      more.complete([
        chunk('!coaches:example.org', 'Coaches', joinRule: 'knock'),
      ]);
      await tester.pump();

      expect(
        find.text('Ask to join • 8 members • Start here if you are new'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      expect(
        requests.map((r) => Uri.decodeComponent(r.url.path)),
        contains('/_matrix/client/v3/knock/!coaches:example.org'),
      );
      expect(find.widgetWithText(OutlinedButton, 'Requested'), findsOneWidget);
      expect(opened, isNull);
    });

    testWidgets('Requested offers to withdraw, which leaves', (tester) async {
      await pump(tester);
      more.complete([
        chunk('!coaches:example.org', 'Coaches', joinRule: 'knock'),
      ]);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      await tester.tap(find.widgetWithText(OutlinedButton, 'Requested'));
      await tester.pumpAndSettle();
      expect(find.text('Withdraw your request?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.url.path.endsWith('/leave')), isEmpty);
      expect(find.widgetWithText(OutlinedButton, 'Requested'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Requested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Withdraw'));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      expect(
        requests.map((r) => Uri.decodeComponent(r.url.path)),
        contains('/_matrix/client/v3/rooms/!coaches:example.org/leave'),
      );
      expect(find.widgetWithText(FilledButton, 'Ask'), findsOneWidget);
    });
  });

  group('people and rules', () {
    void person(String id, String name, {String membership = 'join'}) =>
        club.setState(
          User(id, membership: membership, displayName: name, room: club),
        );

    Future<void> openMembers(WidgetTester tester) async {
      await tester.tap(find.text('24 members'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> network(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    setUp(() {
      person(_me, 'Me');
      person('@maya:example.org', 'Maya');
    });

    testWidgets('admins open Roles & permissions from the menu', (
      tester,
    ) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roles & permissions'));
      await tester.pumpAndSettle();

      expect(find.text('Community defaults'), findsOneWidget);
      expect(find.text('Add rooms'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Climbing club'), findsOneWidget);
    });

    testWidgets('admins open the community settings from the menu', (
      tester,
    ) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community settings'));
      await tester.pumpAndSettle();

      expect(find.text('Community name'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Bouldering on Saturdays'), findsOneWidget);
    });

    testWidgets('banning someone asks first, then bans', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      await openMembers(tester);
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ban from community'));
      await tester.pumpAndSettle();
      expect(find.text('Ban Maya?'), findsOneWidget);
      await tester.tap(find.text('Ban'));
      await network(tester);

      expect(requests.map((r) => r.url.path), contains(endsWith('/ban')));
    });

    testWidgets('a role change that fails says so', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      await openMembers(tester);
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      offline = true;

      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderator').last);
      await network(tester);

      expect(find.text('Role not changed. Try again.'), findsOneWidget);
    });

    testWidgets('a removal that fails says so', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      await openMembers(tester);
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      offline = true;

      await tester.tap(find.text('Remove from community'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await network(tester);

      expect(find.text('Not removed. Try again.'), findsOneWidget);
    });

    testWidgets('the member count opens the members', (tester) async {
      await pump(tester);
      more.complete(const []);

      await openMembers(tester);

      expect(find.text('Maya'), findsOneWidget);
    });

    testWidgets('an admin gives someone a role', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      await openMembers(tester);

      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from community'), findsOneWidget);
      expect(find.text('Ban from community'), findsOneWidget);
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderator').last);
      await network(tester);

      final levels = requests.lastWhere(
        (r) => r.url.path.contains('m.room.power_levels'),
      );
      expect(
        ((jsonDecode(levels.body) as Map)['users'] as Map)['@maya:example.org'],
        50,
      );
    });

    testWidgets('removing someone asks first and says they keep their '
        'rooms', (tester) async {
      makeAdmin();
      await pump(tester);
      more.complete(const []);
      await openMembers(tester);
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove from community'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Maya?'), findsOneWidget);
      expect(
        find.textContaining('They stay in rooms they already joined.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove'));
      await network(tester);

      expect(requests.map((r) => r.url.path), contains(endsWith('/kick')));
    });

    testWidgets('offline, the members already known still show', (
      tester,
    ) async {
      await pump(tester);
      more.complete(const []);
      offline = true;

      await openMembers(tester);

      expect(find.text('Maya'), findsOneWidget);
    });

    testWidgets('a member cannot manage anyone', (tester) async {
      await pump(tester);
      more.complete(const []);
      await openMembers(tester);

      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();

      expect(find.text('Change role'), findsNothing);
      expect(find.text('Remove from community'), findsNothing);
    });
  });

  testWidgets('leaving asks first and names the rooms left with it', (
    tester,
  ) async {
    member('!gear:example.org', 'Gear swap');
    await pump(tester);
    more.complete(const []);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave community'));
    await tester.pumpAndSettle();

    expect(find.text('Leave community?'), findsOneWidget);
    expect(find.text('You also leave Gear swap.'), findsOneWidget);
    expect(requests.where((r) => r.url.path.endsWith('/leave')), isEmpty);
  });

  testWidgets('confirming the leave leaves and closes the page', (
    tester,
  ) async {
    final scope = await overrides();
    await tester.pumpWidget(
      ProviderScope(
        overrides: scope,
        child: MaterialApp(
          theme: zunoLightTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CommunityPage(
                    community: club,
                    loadRooms: (_) async => const [],
                    openRoom: (_, _) {},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave community'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Leave'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(requests.where((r) => r.url.path.endsWith('/leave')), isNotEmpty);
    expect(find.byType(CommunityPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('survives the layout matrix', (tester) async {
    member(
      '!gear:example.org',
      'Gear swap for shoes, harnesses, ropes and everything else',
    );
    putState(club, EventTypes.RoomName, {
      'name': 'The Saturday morning bouldering and climbing club of Lisbon',
    });
    makeAdmin();
    final scope = await overrides();

    await expectSurvivesLayoutMatrix(
      tester,
      () => ProviderScope(
        overrides: scope,
        child: CommunityPage(
          community: club,
          loadRooms: (_) async => [
            chunk(
              '!beginners:example.org',
              'Beginners who have never climbed before',
              members: 12345,
            ),
          ],
          openRoom: (_, _) {},
        ),
      ),
      theme: zunoLightTheme,
      afterEach: (name) async {
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('Join'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Join'), findsOneWidget, reason: name);
        expect(tester.takeException(), isNull, reason: name);
      },
    );
  });
}
