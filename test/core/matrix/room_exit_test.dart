import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/room_exit.dart';

import '../../helpers/fake_matrix.dart';

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
        database: ForgettingFakeDatabaseApi(),
        httpClient: httpClient,
      )
      ..setUserId('@me:example.org')
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'test-token';
  }

  Future<void> endCallsIn(Iterable<String> roomIds) async =>
      requests.add('END ${roomIds.join(',')}');

  Room joinedRoom(Client client) =>
      buildTestRoom(client)..membership = Membership.join;

  Room asLastAdmin(Room room) {
    room.setState(
      Event(
        eventId: '\$power-${room.id}',
        type: EventTypes.RoomPowerLevels,
        senderId: '@me:example.org',
        originServerTs: DateTime(2026),
        content: {
          'users': {'@me:example.org': 100, '@bob:example.org': 0},
        },
        room: room,
        stateKey: '',
      ),
    );
    room.summary.mJoinedMemberCount = 3;
    return room;
  }

  Iterable<String> leaveRequests() =>
      requests.where((r) => r.endsWith('/leave'));

  Iterable<String> forgetRequests() =>
      requests.where((r) => r.endsWith('/forget'));

  Room direct(Room room) {
    room.client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [room.id],
      },
    );
    return room;
  }

  Future<void> tapExit(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  confirmAndExitRoom(context, room, endCallsIn: endCallsIn),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

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
    testWidgets('a room is not left until the prompt is confirmed', (
      tester,
    ) async {
      await tapExit(tester, joinedRoom(exitClient()));

      expect(find.text('Leave room?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Leave'), findsOneWidget);
      expect(leaveRequests(), isEmpty);
    });

    testWidgets('cancelling the prompt leaves the room alone and ends no '
        'call', (tester) async {
      await tapExit(tester, joinedRoom(exitClient()));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsNothing);
      expect(leaveRequests(), isEmpty);
      expect(forgetRequests(), isEmpty);
      expect(requests.where((r) => r.startsWith('END')), isEmpty);
    });

    testWidgets('confirming ends a call in the room before leaving it', (
      tester,
    ) async {
      await tapExit(tester, joinedRoom(exitClient()));

      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(requests.first, 'END !room:example.org');
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
      await tapExit(tester, direct(joinedRoom(exitClient(offline: true))));

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
  });

  group('last admin', () {
    test('leaving a room as its last admin says to hand it on first', () async {
      final room = asLastAdmin(joinedRoom(exitClient()));

      expect(
        await roomExitMessage(room, englishLocalizations),
        'You will stop getting messages here. Make someone else an admin of '
        'this room first, or nobody can manage it again.',
      );
    });

    test('a room with nobody else in it needs no warning', () async {
      final room = asLastAdmin(joinedRoom(exitClient()));
      room.summary.mJoinedMemberCount = 1;

      expect(
        await roomExitMessage(room, englishLocalizations),
        'You will stop getting messages here.',
      );
    });

    test('deleting a chat never warns about admins', () async {
      final room = asLastAdmin(direct(joinedRoom(exitClient())));

      expect(
        await roomExitMessage(room, englishLocalizations),
        isNot(contains('admin')),
      );
    });

    testWidgets('the leave prompt carries the warning', (tester) async {
      await tapExit(tester, asLastAdmin(joinedRoom(exitClient())));

      expect(
        find.textContaining('Make someone else an admin of this room first'),
        findsOneWidget,
      );
    });
  });

  group('labels', () {
    test('a direct chat reads as deleting', () {
      final room = direct(joinedRoom(exitClient()));

      expect(roomExitLabel(room, englishLocalizations), 'Delete chat');
      expect(roomExitConfirmLabel(room, englishLocalizations), 'Delete');
      expect(roomExitTitle(room, englishLocalizations), 'Delete chat?');
    });

    test('a group room reads as leaving', () {
      final room = joinedRoom(exitClient());

      expect(roomExitLabel(room, englishLocalizations), 'Leave room');
      expect(roomExitConfirmLabel(room, englishLocalizations), 'Leave');
      expect(roomExitTitle(room, englishLocalizations), 'Leave room?');
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
        room.setState(
          Event(
            eventId: '\$parent-${room.id}',
            type: EventTypes.SpaceParent,
            senderId: '@me:example.org',
            originServerTs: DateTime(2026),
            content: {
              'via': ['example.org'],
            },
            room: room,
            stateKey: space.id,
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

    test('a community reads as leaving, and names what else is left', () async {
      final client = exitClient();
      final gear = member(client, '!gear:example.org', 'Gear swap');
      final general = member(client, '!general:example.org', 'General');

      final empty = community(buildTestClient(userId: '@me:example.org'));
      expect(roomExitLabel(empty, englishLocalizations), 'Leave community');
      expect(roomExitTitle(empty, englishLocalizations), 'Leave community?');
      expect(roomExitConfirmLabel(empty, englishLocalizations), 'Leave');
      expect(
        await roomExitMessage(empty, englishLocalizations),
        'You will stop seeing its rooms.',
      );

      final one = community(client, rooms: [gear]);
      expect(
        await roomExitMessage(one, englishLocalizations),
        'You also leave Gear swap.',
      );

      client.rooms.remove(one);
      final two = community(client, rooms: [gear, general]);
      expect(
        await roomExitMessage(two, englishLocalizations),
        'You also leave 2 of its rooms.',
      );
    });

    test('a community names what it would leave without an admin', () async {
      final client = exitClient();
      final gear = asLastAdmin(
        member(client, '!gear:example.org', 'Gear swap'),
      );
      final general = member(client, '!general:example.org', 'General');

      final one = community(client, rooms: [gear, general]);
      expect(
        await roomExitMessage(one, englishLocalizations),
        'You also leave 2 of its rooms. Make someone else an admin of Gear '
        'swap first, or nobody can manage it again.',
      );

      asLastAdmin(one);
      asLastAdmin(general);
      expect(
        await roomExitMessage(one, englishLocalizations),
        'You also leave 2 of its rooms. Make someone else an admin of this '
        'community and 2 of its rooms first, or nobody can manage them again.',
      );
    });

    group('names every mix it would leave without an admin', () {
      Future<String> exitMessage({
        required int rooms,
        required bool communityToo,
        int orphaned = 0,
      }) {
        final client = exitClient();
        final members = [
          for (final (i, name) in ['Gear swap', 'General', 'Trips'].indexed)
            if (i < rooms) member(client, '!r$i:example.org', name),
        ];
        members.take(orphaned).forEach(asLastAdmin);
        final space = community(client, rooms: members);
        if (communityToo) asLastAdmin(space);
        return roomExitMessage(space, englishLocalizations);
      }

      test('only the community, with no rooms', () async {
        expect(
          await exitMessage(rooms: 0, communityToo: true),
          'You will stop seeing its rooms. Make someone else an admin of this '
          'community first, or nobody can manage it again.',
        );
      });

      test('only the community, with one room', () async {
        expect(
          await exitMessage(rooms: 1, communityToo: true),
          'You also leave Gear swap. Make someone else an admin of this '
          'community first, or nobody can manage it again.',
        );
      });

      test('only its one room', () async {
        expect(
          await exitMessage(rooms: 1, communityToo: false, orphaned: 1),
          'You also leave Gear swap. Make someone else an admin of Gear swap '
          'first, or nobody can manage it again.',
        );
      });

      test('the community and its one room', () async {
        expect(
          await exitMessage(rooms: 1, communityToo: true, orphaned: 1),
          'You also leave Gear swap. Make someone else an admin of this '
          'community and Gear swap first, or nobody can manage them again.',
        );
      });

      test('only the community, with several rooms', () async {
        expect(
          await exitMessage(rooms: 2, communityToo: true),
          'You also leave 2 of its rooms. Make someone else an admin of this '
          'community first, or nobody can manage it again.',
        );
      });

      test('several of its rooms', () async {
        expect(
          await exitMessage(rooms: 3, communityToo: false, orphaned: 2),
          'You also leave 3 of its rooms. Make someone else an admin of 2 of '
          'its rooms first, or nobody can manage them again.',
        );
      });

      test('the community and one of several rooms', () async {
        expect(
          await exitMessage(rooms: 2, communityToo: true, orphaned: 1),
          'You also leave 2 of its rooms. Make someone else an admin of this '
          'community and Gear swap first, or nobody can manage them again.',
        );
      });
    });

    testWidgets('leaving a community ends a call in any room it takes along', (
      tester,
    ) async {
      final client = exitClient();
      final gear = member(client, '!gear:example.org', 'Gear swap');
      final space = community(client, rooms: [gear]);
      await tapExit(tester, space);

      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(requests.first, 'END ${space.id},!gear:example.org');
      expect(leaveRequests(), isNotEmpty);
    });

    testWidgets('leaving a community while offline says it was not left', (
      tester,
    ) async {
      await tapExit(tester, community(exitClient(offline: true)));
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
