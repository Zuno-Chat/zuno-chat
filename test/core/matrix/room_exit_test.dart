import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_exit.dart';

import '../../helpers/fake_matrix.dart';

class _ForgettableDatabase extends FakeDatabaseApi {
  @override
  Future<void> forgetRoom(String roomId) async {}
}

void main() {
  late List<String> requests;

  Client exitClient({
    int forgetStatus = 200,
    bool refuseLeave = false,
    bool offline = false,
  }) {
    requests = [];
    final httpClient = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (offline) {
        throw http.ClientException('Failed host lookup', request.url);
      }
      if (refuseLeave && request.url.path.endsWith('/leave')) {
        return http.Response(
          jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'Not allowed'}),
          403,
        );
      }
      if (request.url.path.endsWith('/forget')) {
        return http.Response(
          forgetStatus == 200
              ? '{}'
              : jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
          forgetStatus,
        );
      }
      return http.Response('{}', 200);
    });
    return Client(
        'test',
        database: _ForgettableDatabase(),
        httpClient: httpClient,
      )
      ..setUserId('@me:example.org')
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'test-token';
  }

  Room joinedRoom(Client client) =>
      buildTestRoom(client)..membership = Membership.join;

  Iterable<String> leaveRequests() =>
      requests.where((r) => r.endsWith('/leave'));

  Iterable<String> forgetRequests() =>
      requests.where((r) => r.endsWith('/forget'));

  test('a direct chat is left and then forgotten', () async {
    await exitRoom(joinedRoom(exitClient()), isDirect: true);

    expect(leaveRequests(), hasLength(1));
    expect(forgetRequests(), hasLength(1));
    expect(
      requests.indexOf(leaveRequests().first),
      lessThan(requests.indexOf(forgetRequests().first)),
    );
  });

  test('a group room is left but kept', () async {
    await exitRoom(joinedRoom(exitClient()), isDirect: false);

    expect(leaveRequests(), hasLength(1));
    expect(forgetRequests(), isEmpty);
  });

  test('an invitation is left rather than skipped', () async {
    final room = buildTestRoom(exitClient())..membership = Membership.invite;

    await exitRoom(room, isDirect: false);

    expect(leaveRequests(), hasLength(1));
  });

  test('a room that was already left is not left twice', () async {
    final room = buildTestRoom(exitClient())..membership = Membership.leave;

    await exitRoom(room, isDirect: true);

    expect(leaveRequests(), isEmpty);
    expect(forgetRequests(), hasLength(1));
  });

  test('a homeserver that refuses to forget still exits cleanly', () async {
    final room = joinedRoom(exitClient(forgetStatus: 403));

    await expectLater(exitRoom(room, isDirect: true), completes);

    expect(leaveRequests(), hasLength(1));
  });

  group('confirming', () {
    Future<void> tapExit(WidgetTester tester, Room room) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => confirmAndExitRoom(context, room),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('a room is not left until the prompt is confirmed', (
      tester,
    ) async {
      await tapExit(tester, joinedRoom(exitClient()));

      expect(find.text('Leave room?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Leave'), findsOneWidget);
      expect(leaveRequests(), isEmpty);
    });

    testWidgets('cancelling the prompt leaves the room alone', (tester) async {
      await tapExit(tester, joinedRoom(exitClient()));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsNothing);
      expect(leaveRequests(), isEmpty);
      expect(forgetRequests(), isEmpty);
    });

    testWidgets('confirming the prompt leaves the room', (tester) async {
      await tapExit(tester, joinedRoom(exitClient()));

      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(leaveRequests(), hasLength(1));
    });

    testWidgets('leaving while offline says the room was not left', (
      tester,
    ) async {
      await tapExit(tester, joinedRoom(exitClient(offline: true)));

      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not leave the room. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('a refused leave says only that the room was not left, and '
        'logs why', (tester) async {
      final logged = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logged.add(message);
      };
      try {
        await tapExit(tester, joinedRoom(exitClient(refuseLeave: true)));

        await tester.tap(find.widgetWithText(TextButton, 'Leave'));
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
        }
      } finally {
        debugPrint = originalDebugPrint;
      }

      expect(find.text('Could not leave the room.'), findsOneWidget);
      expect(find.textContaining('M_FORBIDDEN'), findsNothing);
      expect(find.textContaining('Not allowed'), findsNothing);
      expect(
        logged,
        contains(allOf(startsWith('zuno/caught:'), contains('M_FORBIDDEN'))),
      );
    });

    testWidgets('deleting a chat while offline says it was not deleted', (
      tester,
    ) async {
      final room = joinedRoom(exitClient(offline: true));
      room.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [room.id],
        },
      );
      await tapExit(tester, room);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not delete the chat. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('a direct chat is prompted as a deletion', (tester) async {
      final room = joinedRoom(exitClient());
      room.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [room.id],
        },
      );

      await tapExit(tester, room);

      expect(find.text('Delete chat?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
      expect(find.text('Leave room?'), findsNothing);
    });
  });

  group('labels', () {
    test('a direct chat reads as deleting', () {
      final room = joinedRoom(exitClient());
      room.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [room.id],
        },
      );

      expect(roomExitLabel(room), 'Delete chat');
      expect(roomExitConfirmLabel(room), 'Delete');
      expect(roomExitTitle(room), 'Delete chat?');
    });

    test('a group room reads as leaving', () {
      final room = joinedRoom(exitClient());

      expect(roomExitLabel(room), 'Leave room');
      expect(roomExitConfirmLabel(room), 'Leave');
      expect(roomExitTitle(room), 'Leave room?');
    });
  });

  group('communities', () {
    Room community(Client client, {List<Room> rooms = const []}) {
      final space = buildTestRoom(client, id: '!club:example.org')
        ..membership = Membership.join;
      space.setState(
        Event(
          eventId: r'$create',
          type: EventTypes.RoomCreate,
          senderId: '@me:example.org',
          originServerTs: DateTime(2026),
          content: {'type': 'm.space'},
          room: space,
          stateKey: '',
        ),
      );
      for (final room in rooms) {
        space.setState(
          Event(
            eventId: '\$child-${room.id}',
            type: EventTypes.SpaceChild,
            senderId: '@me:example.org',
            originServerTs: DateTime(2026),
            content: {
              'via': ['example.org'],
            },
            room: space,
            stateKey: room.id,
          ),
        );
      }
      client.rooms.add(space);
      return space;
    }

    Room member(Client client, String id, String name) {
      final room = buildTestRoom(client, id: id)..membership = Membership.join;
      room.setState(
        Event(
          eventId: '\$name-$id',
          type: EventTypes.RoomName,
          senderId: '@me:example.org',
          originServerTs: DateTime(2026),
          content: {'name': name},
          room: room,
          stateKey: '',
        ),
      );
      client.rooms.add(room);
      return room;
    }

    test(
      'leaving a community leaves its rooms too and forgets nothing',
      () async {
        final client = exitClient();
        final gear = member(client, '!gear:example.org', 'Gear swap');

        await exitRoom(community(client, rooms: [gear]), isDirect: false);

        expect(leaveRequests(), hasLength(2));
        expect(forgetRequests(), isEmpty);
      },
    );

    test('a community reads as leaving, and names what else is left', () {
      final client = exitClient();
      final gear = member(client, '!gear:example.org', 'Gear swap');
      final general = member(client, '!general:example.org', 'General');

      final empty = community(buildTestClient(userId: '@me:example.org'));
      expect(roomExitLabel(empty), 'Leave community');
      expect(roomExitTitle(empty), 'Leave community?');
      expect(roomExitConfirmLabel(empty), 'Leave');
      expect(roomExitMessage(empty), 'You will stop seeing its rooms.');

      final one = community(client, rooms: [gear]);
      expect(roomExitMessage(one), 'You also leave Gear swap.');

      client.rooms.remove(one);
      final two = community(client, rooms: [gear, general]);
      expect(roomExitMessage(two), 'You also leave 2 of its rooms.');
    });

    testWidgets('leaving a community while offline says it was not left', (
      tester,
    ) async {
      final space = community(exitClient(offline: true));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => confirmAndExitRoom(context, space),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Leave community?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not leave the community. Check your connection and try again.',
        ),
        findsOneWidget,
      );
    });
  });
}
