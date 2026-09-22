import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/room_info/presentation/room_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late List<http.Request> requests;
  late Client client;
  late Room room;

  setUp(() {
    requests = [];
    client = buildTestClient(
      userId: '@me:example.org',
      httpClient: MockClient((request) async {
        if (request.url.pathSegments.contains('media')) {
          return http.Response('', 404);
        }
        requests.add(request);
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  void setOwnLevel(int level) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$powerlevels',
      senderId: '@creator:example.org',
      type: EventTypes.RoomPowerLevels,
      stateKey: '',
      content: {
        'users': {'@me:example.org': level},
      },
    ),
  );

  void setJoinRule(String rule) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$join',
      senderId: '@creator:example.org',
      type: EventTypes.RoomJoinRules,
      stateKey: '',
      content: {'join_rule': rule},
    ),
  );

  void setRoomState(String type, Map<String, Object?> content) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$state-' + type,
      senderId: '@creator:example.org',
      type: type,
      stateKey: '',
      content: content,
    ),
  );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: RoomSettingsPage(room: room)));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  ListTile accessRow(WidgetTester tester) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Room access'));

  Future<void> pickAccess(WidgetTester tester, String label) async {
    await tester.tap(find.text('Room access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('an admin makes the room public after confirming', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expect(find.text('Room access'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);

    await pickAccess(tester, 'Public');

    expect(find.text('Make room public?'), findsOneWidget);
    expect(find.textContaining('can find it'), findsOneWidget);
    expect(find.textContaining('join without an invite'), findsOneWidget);
    expect(find.textContaining('read older messages'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(find.text('Make public'));
    await settle(tester);

    expect(requests.map((r) => r.url.pathSegments), [
      contains('directory'),
      contains('m.room.join_rules'),
    ]);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Room access updated'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    await pickAccess(tester, 'Public');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(requests, isEmpty);
    expect(find.text('Make room public?'), findsNothing);
    expect(find.text('Private'), findsOneWidget);
  });

  testWidgets('making a public room private explains what changes', (
    tester,
  ) async {
    setOwnLevel(100);
    setJoinRule('public');
    await pumpPage(tester);

    await pickAccess(tester, 'Private');

    expect(find.text('Make room private?'), findsOneWidget);
    expect(find.textContaining('leaves the public list'), findsOneWidget);
    expect(find.textContaining('need an invite'), findsOneWidget);
    expect(find.textContaining('Nobody is removed'), findsOneWidget);

    await tester.tap(find.text('Make private'));
    await settle(tester);

    expect(requests.map((r) => r.url.pathSegments), [
      contains('m.room.join_rules'),
      contains('directory'),
    ]);
    expect(find.text('Private'), findsOneWidget);
  });

  testWidgets('a moderator sees the access but cannot change it', (
    tester,
  ) async {
    setOwnLevel(50);
    await pumpPage(tester);

    expect(find.text('Private'), findsOneWidget);
    expect(accessRow(tester).onTap, isNull);
  });

  testWidgets('a direct chat has no access row', (tester) async {
    setOwnLevel(100);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [room.id],
      },
    );
    await pumpPage(tester);

    expect(find.text('Room access'), findsNothing);
  });

  testWidgets('the main address hides the server', (tester) async {
    setOwnLevel(100);
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$alias',
        senderId: '@creator:example.org',
        type: EventTypes.RoomCanonicalAlias,
        stateKey: '',
        content: {'alias': '#chess:example.org'},
      ),
    );
    await pumpPage(tester);

    expect(find.text('#chess'), findsOneWidget);
    expect(find.textContaining('example.org'), findsNothing);

    await tester.tap(find.text('Main address'));
    await tester.pumpAndSettle();

    expect(find.textContaining('example.org'), findsNothing);
  });

  testWidgets('clearing the main address removes it', (tester) async {
    setOwnLevel(100);
    setRoomState(EventTypes.RoomCanonicalAlias, {
      'alias': '#chess:example.org',
    });
    await pumpPage(tester);

    await tester.tap(find.text('Main address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(requests, hasLength(2));
    expect(requests[0].method, 'DELETE');
    expect(requests[0].url.pathSegments.last, '#chess:example.org');
    expect(requests[1].url.pathSegments, contains('m.room.canonical_alias'));
    expect(jsonDecode(requests[1].body), <String, Object?>{});
    expect(find.text('#chess'), findsNothing);
    expect(find.text('#'), findsNothing);
  });

  testWidgets('editors cap name, topic and address lengths', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    for (final (row, limit) in [
      ('Room name', 50),
      ('Topic', 250),
      ('Main address', 50),
    ]) {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x' * (limit + 20));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, limit, reason: row);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a room cannot be renamed after Zuno', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    await tester.tap(find.text('Room name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Zun0 support');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot include Zuno'), findsOneWidget);
    expect(requests.where((r) => r.url.path.contains('m.room.name')), isEmpty);
  });

  testWidgets('the topic row shows at most three lines', (tester) async {
    setOwnLevel(100);
    const topic = 'one\ntwo\nthree\nfour\nfive';
    setRoomState(EventTypes.RoomTopic, {'topic': topic});
    await pumpPage(tester);

    final text = tester.widget<Text>(find.text(topic));
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('removing the photo clears it at once', (tester) async {
    setOwnLevel(100);
    setRoomState(EventTypes.RoomAvatar, {'url': 'mxc://example.org/old'});
    await pumpPage(tester);

    await tester.tap(find.text('Room photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await settle(tester);

    expect(requests, hasLength(1));
    expect(requests.single.url.pathSegments, contains('m.room.avatar'));
    expect(jsonDecode(requests.single.body), <String, Object?>{});
    expect(room.avatar, isNull);
    expect(find.text('Photo updated'), findsOneWidget);
  });
}
