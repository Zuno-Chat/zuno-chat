import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/media/avatars/mxc_avatar.dart';
import 'package:zuno/features/chat/presentation/message_tile.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

class _StoredMembersDb extends StoredEventsFakeDatabaseApi {
  int memberLoads = 0;

  @override
  Future<List<User>> getUsers(Room room) async {
    if (memberLoads++ >= 3) return [];
    return [
      User('@me:example.org', membership: 'join', room: room),
      User('@bob:example.org', membership: 'join', room: room),
    ];
  }

  @override
  Future<List<Event>> getUnimportantRoomEventStatesForRoom(
    List<String> events,
    Room room,
  ) async => [];
}

void main() {
  testWidgets('opening a room loads no members', (tester) async {
    final db = _StoredMembersDb();
    final harness = RoomPageHarness(db: db);
    harness.room.partial = true;

    await harness.pumpRoomPage(tester);
    await harness.settle(tester);

    expect(db.memberLoads, 0);
  });

  testWidgets('tapping a face opens that person, and only then asks which '
      'rooms you share', (tester) async {
    final harness = RoomPageHarness(db: SendingFakeDatabaseApi());
    harness.respond = (request) {
      if (request.url.path.endsWith('/versions')) {
        return http.Response(
          jsonEncode({
            'versions': ['v1.19'],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/mutual_rooms')) {
        return http.Response('{"joined":[],"count":0}', 200);
      }
      return null;
    };
    harness.db.events = [harness.message(r'$1')];

    await harness.pumpRoomPage(tester);
    expect(harness.requests.where((p) => p.endsWith('/mutual_rooms')), isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byType(MessageTile),
        matching: find.byType(MxcAvatar),
      ),
    );
    await harness.settle(tester);

    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('@bob'),
      ),
      findsOneWidget,
    );
    expect(
      harness.requests.where((p) => p.endsWith('/mutual_rooms')),
      hasLength(1),
    );
  });
}
