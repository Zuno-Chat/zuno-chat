import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/communities/presentation/join_requests_view.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/layout_matrix.dart';
import '../../../helpers/pump_until.dart';

const _me = '@me:example.org';

class _CountingDatabase extends FakeDatabaseApi with SendCapableDatabase {
  int memberReads = 0;

  @override
  Future<List<User>> getUsers(Room room) async {
    memberReads++;
    return [];
  }
}

void main() {
  late Client client;
  late Room room;
  late List<http.Request> requests;
  late bool offline;

  setUp(() {
    requests = [];
    offline = false;
    client = buildTestClient(
      userId: _me,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (offline) {
          throw http.ClientException('Failed host lookup', request.url);
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client, id: '!beginners:example.org')
      ..membership = Membership.join
      ..partial = false;
    room.setState(
      Event(
        eventId: r'$name',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: _me,
        originServerTs: DateTime(2026),
        content: {'name': 'Beginners'},
        room: room,
      ),
    );
    room.setState(User(_me, membership: 'join', room: room));
    client.rooms.add(room);
  });

  void levels(int mine) => room.setState(
    Event(
      eventId: r'$levels',
      type: EventTypes.RoomPowerLevels,
      stateKey: '',
      senderId: '@admin:example.org',
      originServerTs: DateTime(2026),
      content: {
        'users': {_me: mine},
        'invite': 0,
        'kick': 50,
      },
      room: room,
    ),
  );

  void asking(String userId, String name) => room.setState(
    User(userId, membership: 'knock', displayName: name, room: room),
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(body: Column(children: [child])),
      ),
    );
    await tester.pump();
  }

  Future<void> network(WidgetTester tester) async {
    await pumpRealAsync(tester, rounds: 3);
  }

  Iterable<String> calls() => requests.map((r) => r.url.pathSegments.last);

  group('the card in the chat', () {
    testWidgets('shows nothing to someone who cannot answer', (tester) async {
      levels(0);
      asking('@maya:example.org', 'Maya');

      await pump(tester, JoinRequestsBanner(room: room));

      expect(find.text('Maya'), findsNothing);
      expect(find.text('Let in'), findsNothing);
    });

    testWidgets('shows nothing when nobody is asking', (tester) async {
      levels(50);

      await pump(tester, JoinRequestsBanner(room: room));

      expect(
        find.descendant(
          of: find.byType(JoinRequestsBanner),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
      expect(find.text('Let in'), findsNothing);
    });

    testWidgets('one request can be answered right there', (tester) async {
      levels(50);
      asking('@maya:example.org', 'Maya');
      await pump(tester, JoinRequestsBanner(room: room));

      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('Asks to join'), findsOneWidget);

      await tester.tap(find.text('Let in'));
      await network(tester);

      expect(calls(), ['invite']);
      expect(jsonDecode(requests.single.body), {
        'user_id': '@maya:example.org',
      });
      expect(find.text('Maya'), findsNothing);
    });

    testWidgets('Decline removes the request', (tester) async {
      levels(50);
      asking('@maya:example.org', 'Maya');
      await pump(tester, JoinRequestsBanner(room: room));

      await tester.tap(find.text('Decline'));
      await network(tester);

      expect(calls(), ['kick']);
      expect(find.text('Maya'), findsNothing);
    });

    testWidgets('an answer that cannot be sent says so and keeps the '
        'request', (tester) async {
      levels(50);
      asking('@maya:example.org', 'Maya');
      offline = true;
      await pump(tester, JoinRequestsBanner(room: room));

      await tester.tap(find.text('Let in'));
      await network(tester);

      expect(
        find.text(
          'Could not let them in. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Maya'), findsOneWidget);
    });

    testWidgets('several requests open a sheet that closes when all are '
        'answered', (tester) async {
      levels(50);
      asking('@maya:example.org', 'Maya');
      asking('@leo:example.org', 'Leo');
      await pump(tester, JoinRequestsBanner(room: room));

      expect(find.textContaining('and 1 other'), findsOneWidget);
      expect(find.text('Ask to join'), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );
      expect(find.text('Asking to join Beginners'), findsOneWidget);
      expect(inSheet('Let in'), findsNWidgets(2));

      await tester.tap(inSheet('Let in').first);
      await network(tester);
      expect(inSheet('Let in'), findsOneWidget);

      await tester.tap(inSheet('Decline'));
      await network(tester);
      await tester.pumpAndSettle();

      client.onRoomState.add((
        roomId: room.id,
        state: User('@leo:example.org', membership: 'leave', room: room),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Asking to join Beginners'), findsNothing);
      expect(find.byType(JoinRequestsBanner), findsOneWidget);
      expect(calls(), unorderedEquals(['invite', 'kick']));
      expect(find.text('Let in'), findsNothing);
      expect(find.text('Review'), findsNothing);
    });

    testWidgets('survives the layout matrix, one request or several', (
      tester,
    ) async {
      levels(50);
      asking('@maya:example.org', 'Maya Silva de Oliveira Costa');
      Widget banner() => Scaffold(
        body: Column(children: [JoinRequestsBanner(room: room)]),
      );

      await expectSurvivesLayoutMatrix(tester, banner, theme: zunoLightTheme);

      asking('@leo:example.org', 'Leonardo Park');
      await expectSurvivesLayoutMatrix(tester, banner, theme: zunoLightTheme);
    });
  });

  group('loading', () {
    late _CountingDatabase database;

    setUp(() {
      database = _CountingDatabase();
      client = buildTestClient(
        userId: _me,
        database: database,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'chunk': [
                {
                  'type': EventTypes.RoomMember,
                  'state_key': '@maya:example.org',
                  'sender': '@maya:example.org',
                  'event_id': r'$maya',
                  'origin_server_ts': 0,
                  'content': {'membership': 'knock', 'displayname': 'Maya'},
                },
              ],
            }),
            200,
          ),
        ),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      room = buildTestRoom(client, id: '!beginners:example.org')
        ..membership = Membership.join
        ..partial = false;
      room.setState(User(_me, membership: 'join', room: room));
      client.rooms.add(room);
      levels(50);
    });

    void joinRule(String rule) => room.setState(
      Event(
        eventId: r'$rule',
        type: EventTypes.RoomJoinRules,
        stateKey: '',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2026),
        content: {'join_rule': rule},
        room: room,
      ),
    );

    testWidgets('requests are looked up where people can ask', (tester) async {
      joinRule('knock');

      await pump(tester, JoinRequestsBanner(room: room));
      await network(tester);

      expect(database.memberReads, 1);
      expect(find.text('Maya'), findsOneWidget);
    });

    testWidgets('and nowhere else', (tester) async {
      joinRule('invite');

      await pump(tester, JoinRequestsBanner(room: room));
      await network(tester);

      expect(database.memberReads, 0);
    });
  });

  group('room info', () {
    testWidgets('lists the requests for those who can answer', (tester) async {
      levels(100);
      asking('@maya:example.org', 'Maya');

      await pump(tester, JoinRequestsSection(room: room));

      expect(find.text('Asking to join'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('@maya'), findsOneWidget);

      await tester.tap(find.text('Let in'));
      await network(tester);

      expect(find.text('Asking to join'), findsNothing);
    });

    testWidgets('lists nothing for members', (tester) async {
      levels(0);
      asking('@maya:example.org', 'Maya');

      await pump(tester, JoinRequestsSection(room: room));

      expect(find.text('Asking to join'), findsNothing);
    });
  });
}
