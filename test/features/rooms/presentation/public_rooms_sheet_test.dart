import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/rooms/presentation/public_rooms_sheet.dart';

import '../../../helpers/fake_matrix.dart';

PublishedRoomsChunk _room(
  String id, {
  String? name,
  String? alias,
  String? topic,
  int members = 3,
  String? roomType,
}) => PublishedRoomsChunk(
  roomId: id,
  name: name,
  canonicalAlias: alias,
  topic: topic,
  numJoinedMembers: members,
  roomType: roomType,
  guestCanJoin: false,
  worldReadable: false,
);

QueryPublicRoomsResponse _page(
  List<PublishedRoomsChunk> rooms, {
  String? next,
}) => QueryPublicRoomsResponse(chunk: rooms, nextBatch: next);

class _Opened {
  final calls = <({String? term, String? since})>[];
  Future<String?>? result;
}

Future<_Opened> _open(
  WidgetTester tester,
  PublicRoomsSearch search, {
  Client? client,
}) async {
  final opened = _Opened();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final testClient = client ?? buildTestClient(userId: '@me:example.org');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => opened.result = showPublicRoomsSheet(
              context,
              client: testClient,
              search: ({term, since}) {
                opened.calls.add((term: term, since: since));
                return search(term: term, since: since);
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('lists the directory on open', (tester) async {
    final opened = await _open(
      tester,
      ({term, since}) async => _page([
        _room(
          '!a:example.org',
          name: 'Chess club',
          topic: 'Openings and endgames',
          members: 12,
        ),
        _room('!b:example.org', name: 'Gardening', members: 1),
      ]),
    );

    expect(opened.calls, [(term: null, since: null)]);
    expect(find.text('Chess club'), findsOneWidget);
    expect(find.text('Openings and endgames'), findsOneWidget);
    expect(find.text('12 members'), findsOneWidget);
    expect(find.text('Gardening'), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);
  });

  testWidgets('hands back the room id on tap', (tester) async {
    final opened = await _open(
      tester,
      ({term, since}) async =>
          _page([_room('!a:example.org', name: 'Chess club')]),
    );

    await tester.tap(find.text('Chess club'));
    await tester.pumpAndSettle();

    expect(await opened.result, '!a:example.org');
  });

  testWidgets('falls back to the local alias, then the local id', (
    tester,
  ) async {
    await _open(
      tester,
      ({term, since}) async => _page([
        _room('!a:example.org', alias: '#chess:example.org'),
        _room('!b:example.org'),
      ]),
    );

    expect(find.text('#chess'), findsOneWidget);
    expect(find.text('!b'), findsOneWidget);
  });

  testWidgets('narrows the list as you type, once you pause', (tester) async {
    final opened = await _open(
      tester,
      ({term, since}) async => _page(
        term == 'chess'
            ? [_room('!a:example.org', name: 'Chess club')]
            : [_room('!b:example.org', name: 'Gardening')],
      ),
    );

    await tester.enterText(find.byType(TextField), 'ch');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'chess');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(opened.calls.map((c) => c.term), [null, 'chess']);
    expect(find.text('Chess club'), findsOneWidget);
    expect(find.text('Gardening'), findsNothing);
  });

  testWidgets('ignores a stale response that lands after a newer search', (
    tester,
  ) async {
    final slow = Completer<QueryPublicRoomsResponse>();
    await _open(
      tester,
      ({term, since}) => switch (term) {
        'ch' => slow.future,
        'chess' => Future.value(
          _page([_room('!a:example.org', name: 'Chess club')]),
        ),
        _ => Future.value(_page([])),
      },
    );

    await tester.enterText(find.byType(TextField), 'ch');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'chess');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    slow.complete(_page([_room('!b:example.org', name: 'Gardening')]));
    await tester.pumpAndSettle();

    expect(find.text('Chess club'), findsOneWidget);
    expect(find.text('Gardening'), findsNothing);
  });

  testWidgets('tags rooms you already belong to', (tester) async {
    final client = buildTestClient(userId: '@me:example.org');
    client.rooms.add(buildTestRoom(client, id: '!a:example.org'));
    client.rooms.add(
      Room(id: '!c:example.org', client: client, membership: Membership.leave),
    );
    await _open(
      tester,
      ({term, since}) async => _page([
        _room('!a:example.org', name: 'Chess club'),
        _room('!b:example.org', name: 'Gardening'),
        _room('!c:example.org', name: 'Knitting'),
      ]),
      client: client,
    );

    expect(find.text('Joined'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Joined'), matching: find.byType(ListTile)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Chess club'),
          matching: find.byType(ListTile),
        ),
        matching: find.text('Joined'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hides spaces', (tester) async {
    await _open(
      tester,
      ({term, since}) async => _page([
        _room('!s:example.org', name: 'A space', roomType: 'm.space'),
        _room('!a:example.org', name: 'Chess club'),
      ]),
    );

    expect(find.text('A space'), findsNothing);
    expect(find.text('Chess club'), findsOneWidget);
  });

  testWidgets('says so when nothing matches', (tester) async {
    await _open(tester, ({term, since}) async => _page([]));

    expect(find.text('No rooms found'), findsOneWidget);
  });

  testWidgets('offers a retry when loading fails', (tester) async {
    var failing = true;
    await _open(tester, ({term, since}) async {
      if (failing) throw Exception('boom');
      return _page([_room('!a:example.org', name: 'Chess club')]);
    });

    expect(find.text('Could not load rooms'), findsOneWidget);
    expect(find.text('Chess club'), findsNothing);

    failing = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load rooms'), findsNothing);
    expect(find.text('Chess club'), findsOneWidget);
  });

  testWidgets('loads the next page when the end comes into view', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      ({term, since}) async => since == null
          ? _page([
              _room('!a:example.org', name: 'Room A'),
              _room('!b:example.org', name: 'Room B'),
              _room('!c:example.org', name: 'Room C'),
            ], next: 'page2')
          : _page([_room('!d:example.org', name: 'Room D')]),
    );

    expect(opened.calls, [
      (term: null, since: null),
      (term: null, since: 'page2'),
    ]);
    expect(find.text('Room D'), findsOneWidget);
  });
}
