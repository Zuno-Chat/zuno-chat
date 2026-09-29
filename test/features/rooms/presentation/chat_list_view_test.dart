import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/communities.dart';
import 'package:zuno/core/ui/empty_state.dart';
import 'package:zuno/core/ui/section_label.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/chat_wallpaper.dart';
import 'package:zuno/features/rooms/presentation/chat_list_view.dart';
import 'package:zuno/features/rooms/presentation/chat_row.dart';
import 'package:zuno/features/rooms/presentation/invitation_group.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/layout_matrix.dart';

void main() {
  late Client client;

  setUp(() {
    client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    client.setUserId('@me:example.org');
  });

  Room joined(String id, String body) {
    final room = buildTestRoom(client, id: id)..partial = false;
    room.setState(
      buildTestEvent(
        room,
        eventId: '\$name-$id',
        senderId: '@me:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Room $id'},
      ),
    );
    room.lastEvent = buildTestEvent(
      room,
      eventId: '\$msg-$id',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': body},
      originServerTs: DateTime(2026, 9, 20, 9, 41),
    );
    return room;
  }

  Room invitation(String id) =>
      buildTestRoom(client, id: id)..membership = Membership.invite;

  Future<void> pump(
    WidgetTester tester,
    List<Room> rooms, {
    bool communities = false,
    void Function(Room)? onOpen,
    void Function(Room)? onActions,
  }) async {
    final layout = arrangeHome(rooms);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(
          body: communities
              ? ChatListView.communities(
                  client: client,
                  layout: layout,
                  unreadCorrections: const {},
                  onOpen: onOpen ?? (_) {},
                  onActions: onActions ?? (_) {},
                )
              : ChatListView.chats(
                  client: client,
                  layout: layout,
                  unreadCorrections: const {},
                  onOpen: onOpen ?? (_) {},
                  onActions: onActions ?? (_) {},
                ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the chat list loads the chat wallpaper ahead of the first '
      'chat, after its own first frame', (tester) async {
    imageCache.clear();
    await pump(tester, const []);

    final context = tester.element(find.byType(ChatListView));
    final key = await tester.runAsync(
      () =>
          const AssetImage(chatWallpaperAsset)
              .obtainKey(createLocalImageConfiguration(context)),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(imageCache.containsKey(key!), isTrue);
  });

  testWidgets('nothing at all shows the empty state', (tester) async {
    await pump(tester, []);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.text('Tap + to start one.'), findsOneWidget);
    expect(find.byType(SectionLabel), findsNothing);
  });

  testWidgets('chats alone get no labels', (tester) async {
    await pump(tester, [joined('!a:example.org', 'hello')]);

    expect(find.byType(ChatRow), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(SectionLabel), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('invitations get their own labeled group above the chats', (
    tester,
  ) async {
    await pump(tester, [
      joined('!a:example.org', 'hello'),
      invitation('!i:example.org'),
    ]);

    expect(find.text('Invitations'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.byType(InvitationGroup), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(InvitationGroup)).dy,
      lessThan(tester.getTopLeft(find.byType(ChatRow)).dy),
    );
  });

  testWidgets('an invitation with no chats still shows, without empty state', (
    tester,
  ) async {
    await pump(tester, [invitation('!i:example.org')]);

    expect(find.byType(InvitationGroup), findsOneWidget);
    expect(find.text('Invitations'), findsOneWidget);
    expect(find.text('Chats'), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('an invitation sits on its own tinted ink surface', (
    tester,
  ) async {
    await pump(tester, [invitation('!i:example.org')]);

    final surface = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Invited you to chat'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.color, zunoLightTheme.colorScheme.secondaryContainer);
    expect(surface.elevation, 0);
  });

  testWidgets('an unchanged room keeps the identical row across rebuilds', (
    tester,
  ) async {
    final rooms = [joined('!a:example.org', 'hello')];
    await pump(tester, rooms);
    final before = tester.widget<ChatRow>(find.byType(ChatRow));

    await pump(tester, rooms);
    final after = tester.widget<ChatRow>(find.byType(ChatRow));

    expect(identical(before, after), isTrue);
  });

  testWidgets('a new message gives that room a new row', (tester) async {
    final room = joined('!a:example.org', 'hello');
    await pump(tester, [room]);
    final before = tester.widget<ChatRow>(find.byType(ChatRow));

    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$newer',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'are you there'},
    );
    await pump(tester, [room]);

    expect(
      identical(before, tester.widget<ChatRow>(find.byType(ChatRow))),
      isFalse,
    );
    expect(find.text('are you there'), findsOneWidget);
  });

  testWidgets('tapping and long-pressing a row report its room', (
    tester,
  ) async {
    final room = joined('!a:example.org', 'hello');
    Room? opened;
    Room? actedOn;
    await pump(
      tester,
      [room],
      onOpen: (r) => opened = r,
      onActions: (r) => actedOn = r,
    );

    await tester.tap(find.byType(ChatRow));
    await tester.longPress(find.byType(ChatRow));

    expect(opened, same(room));
    expect(actedOn, same(room));
  });

  Room community(String id, String name, List<Room> rooms) {
    final space = buildTestRoom(client, id: id)..partial = false;
    space.setState(
      buildTestEvent(
        space,
        eventId: '\$create-$id',
        senderId: '@me:example.org',
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': 'm.space'},
        originServerTs: DateTime(2026, 1, 1),
      ),
    );
    space.setState(
      buildTestEvent(
        space,
        eventId: '\$name-$id',
        senderId: '@me:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': name},
      ),
    );
    for (final room in rooms) {
      space.setState(
        buildTestEvent(
          space,
          eventId: '\$child-${room.id}',
          senderId: '@me:example.org',
          type: EventTypes.SpaceChild,
          stateKey: room.id,
          content: {
            'via': ['example.org'],
          },
        ),
      );
    }
    client.rooms.addAll([...rooms, space]);
    return space;
  }

  testWidgets('chats never show a community or its rooms', (tester) async {
    final chat = joined('a', 'hello');
    final gear = joined('gear', 'spare shoes in 41');
    community('!club', 'Climbing club', [gear]);
    client.rooms.add(chat);

    await pump(tester, client.rooms);

    expect(find.byType(ChatRow), findsOneWidget);
    expect(find.text('Room a'), findsOneWidget);
    expect(find.text('Climbing club'), findsNothing);
    expect(find.text('spare shoes in 41'), findsNothing);
  });

  testWidgets('communities show one row each with their newest room, and no '
      'chats', (tester) async {
    final chat = joined('a', 'hello');
    final gear = joined('gear', 'spare shoes in 41');
    community('!club', 'Climbing club', [gear]);
    client.rooms.add(chat);

    await pump(tester, client.rooms, communities: true);

    expect(find.byType(ChatRow), findsOneWidget);
    expect(find.text('Climbing club'), findsOneWidget);
    expect(find.text('Room gear ·', findRichText: true), findsOneWidget);
    expect(find.text('spare shoes in 41'), findsOneWidget);
    expect(find.text('Room a'), findsNothing);
  });

  testWidgets('no communities shows its own empty state', (tester) async {
    client.rooms.add(joined('a', 'hello'));

    await pump(tester, client.rooms, communities: true);

    expect(find.text('No communities yet'), findsOneWidget);
    expect(
      find.text('Tap + to start one or find a public one.'),
      findsOneWidget,
    );
    expect(find.byType(ChatRow), findsNothing);
  });

  testWidgets('community invitations sit above the communities', (
    tester,
  ) async {
    community('!club', 'Climbing club', const []);
    community('!other', 'Rivera family', const []).membership =
        Membership.invite;

    await pump(tester, client.rooms, communities: true);

    expect(find.text('Invitations'), findsOneWidget);
    expect(find.text('Communities'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(InvitationGroup)).dy,
      lessThan(tester.getTopLeft(find.byType(ChatRow)).dy),
    );
  });

  testWidgets('tapping and long-pressing a community report the community', (
    tester,
  ) async {
    final club = community('!club', 'Climbing club', [joined('gear', 'hi')]);
    Room? opened;
    Room? actedOn;

    await pump(
      tester,
      client.rooms,
      communities: true,
      onOpen: (r) => opened = r,
      onActions: (r) => actedOn = r,
    );
    await tester.tap(find.text('Climbing club'));
    await tester.longPress(find.text('Climbing club'));

    expect(opened, club);
    expect(actedOn, club);
  });

  testWidgets('a community with none of its rooms joined says so', (
    tester,
  ) async {
    community('!club', 'Climbing club', const []);

    await pump(tester, client.rooms, communities: true);

    expect(find.text('Climbing club'), findsOneWidget);
    expect(find.text('No rooms joined yet'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('a community row survives the layout matrix', (tester) async {
    final gear = joined(
      'gear',
      'Maya: I have spare shoes in size 41 if anyone needs them',
    );
    community('!club', 'The Saturday morning bouldering club of Lisbon', [
      gear,
    ]);

    await expectSurvivesLayoutMatrix(
      tester,
      () => Scaffold(
        body: ChatListView.communities(
          client: client,
          layout: arrangeHome(client.rooms),
          unreadCorrections: const {},
          onOpen: (_) {},
          onActions: (_) {},
        ),
      ),
      theme: zunoLightTheme,
    );
  });

  testWidgets('the list ends with a little room to breathe', (tester) async {
    await pump(tester, [joined('!a:example.org', 'hello')]);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
    final last =
        tester
                .widget<CustomScrollView>(find.byType(CustomScrollView))
                .slivers
                .last
            as SliverToBoxAdapter;
    expect((last.child! as SizedBox).height, 12);
  });

  testWidgets('a chat that jumps to the top leaves the other rows mounted', (
    tester,
  ) async {
    final a = joined('!a:example.org', 'first');
    final b = joined('!b:example.org', 'second');
    final c = joined('!c:example.org', 'third');
    await pump(tester, [a, b, c]);
    Element row(Room room) => tester.element(find.byKey(ValueKey(room.id)));
    final rowA = row(a);
    final rowB = row(b);

    await pump(tester, [c, a, b]);

    expect(identical(row(a), rowA), isTrue);
    expect(identical(row(b), rowB), isTrue);
    expect(
      tester.getTopLeft(find.byKey(ValueKey(c.id))).dy,
      lessThan(tester.getTopLeft(find.byKey(ValueKey(a.id))).dy),
    );
  });
}
