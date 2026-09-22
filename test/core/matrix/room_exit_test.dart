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

  Client exitClient({int forgetStatus = 200}) {
    requests = [];
    final httpClient = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
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
}
