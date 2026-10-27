import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/mxc_avatar.dart';
import 'package:zuno/core/matrix/optimistic_room_state.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/features/share/presentation/forward_picker_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/route_launcher.dart';

void main() {
  late Client client;
  List<Room>? picked;
  var returned = false;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org', encrypting: true);
    picked = null;
    returned = false;
  });

  Room named(
    String id,
    String name, {
    bool encrypted = true,
    Membership membership = Membership.join,
  }) =>
      namedRoom(client, id, name, encrypted: encrypted, membership: membership);

  Future<void> openPicker(
    WidgetTester tester, {
    bool fromEncrypted = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: routeLauncher<List<Room>>(
          (_) =>
              ForwardPickerPage(client: client, fromEncrypted: fromEncrypted),
          onResult: (result) {
            picked = result;
            returned = true;
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder rowOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));

  bool ticked(WidgetTester tester, String name) => tester
      .widget<Checkbox>(
        find.descendant(of: rowOf(name), matching: find.byType(Checkbox)),
      )
      .value!;

  FilledButton sendButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'));

  testWidgets(
    'lists the chats the share picker lists, with a red lock on unencrypted ones',
    (tester) async {
      client.rooms = [
        named('!a:example.org', 'Alice'),
        named('!b:example.org', 'Bob', encrypted: false),
        named('!i:example.org', 'Invite', membership: Membership.invite),
      ];
      await openPicker(tester);

      expect(find.text('Forward to'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Invite'), findsNothing);
      final lock = find.byIcon(notEncryptedIcon);
      expect(lock, findsOneWidget);
      expect(find.descendant(of: rowOf('Bob'), matching: lock), findsOneWidget);
      final context = tester.element(lock);
      expect(
        tester.widget<Icon>(lock).color,
        Theme.of(context).colorScheme.error,
      );
    },
  );

  testWidgets('a chat in a community carries the community avatar in its '
      'corner; other groups keep the group mark', (tester) async {
    final crew = named('!crew:example.org', 'Belay crew');
    final other = named('!other:example.org', 'Book club');
    final club = named('!club:example.org', 'Climbing club');
    applyOptimisticRoomState(club, EventTypes.RoomCreate, {'type': 'm.space'});
    applyOptimisticRoomState(club, EventTypes.SpaceChild, {
      'via': ['example.org'],
    }, stateKey: crew.id);
    applyOptimisticRoomState(crew, EventTypes.SpaceParent, {
      'via': ['example.org'],
    }, stateKey: club.id);
    client.rooms = [crew, other, club];
    await openPicker(tester);

    final badge = find.descendant(
      of: rowOf('Belay crew'),
      matching: find.byWidgetPredicate(
        (w) => w is MxcAvatar && w.fallbackText == 'Climbing club',
      ),
    );
    expect(badge, findsOneWidget);
    expect(tester.widget<MxcAvatar>(badge).shape, AvatarShape.roundedSquare);
    expect(
      find.descendant(
        of: rowOf('Belay crew'),
        matching: find.byIcon(Icons.groups),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: rowOf('Book club'),
        matching: find.byIcon(Icons.groups),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ticks up to 5 chats, and a sixth says so and stays unticked', (
    tester,
  ) async {
    final names = ['Ana', 'Ben', 'Cy', 'Dee', 'Eve', 'Fox'];
    client.rooms = [
      for (final (i, name) in names.indexed) named('!$i:example.org', name),
    ];
    await openPicker(tester);

    for (final name in names) {
      await tester.tap(find.text(name));
      await tester.pump();
    }

    expect(find.text('You can forward to up to 5 chats.'), findsOneWidget);
    expect(
      [for (final name in names) ticked(tester, name)],
      [true, true, true, true, true, false],
    );
  });

  testWidgets(
    'Send is off until a chat is ticked, and returns the ticked chats',
    (tester) async {
      client.rooms = [
        named('!a:example.org', 'Alice'),
        named('!b:example.org', 'Bob'),
        named('!c:example.org', 'Cleo'),
      ];
      await openPicker(tester);

      expect(sendButton(tester).onPressed, isNull);

      await tester.tap(find.text('Cleo'));
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Cleo'));
      await tester.tap(find.text('Bob'));
      await tester.pump();
      expect(sendButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(picked!.map((r) => r.id), ['!a:example.org', '!b:example.org']);
      expect(find.text('Forward to'), findsNothing);
    },
  );

  testWidgets('a ticked chat that drops out of the list is no longer ticked '
      'or sent to', (tester) async {
    final bob = named('!b:example.org', 'Bob');
    client.rooms = [named('!a:example.org', 'Alice'), bob];
    await openPicker(tester);
    await tester.tap(find.text('Alice'));
    await tester.tap(find.text('Bob'));
    await tester.pump();

    bob.membership = Membership.leave;
    client.onSync.add(SyncUpdate(nextBatch: ''));
    await tester.pump();
    expect(find.text('Bob'), findsNothing);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(picked!.map((r) => r.id), ['!a:example.org']);
  });

  testWidgets('going back returns nothing', (tester) async {
    client.rooms = [named('!a:example.org', 'Alice')];
    await openPicker(tester);

    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(picked, isNull);
  });

  testWidgets(
    'from an encrypted chat, ticking an unencrypted chat shows the note; unticking hides it',
    (tester) async {
      client.rooms = [
        named('!a:example.org', 'Alice'),
        named('!b:example.org', 'Bob', encrypted: false),
      ];
      await openPicker(tester);

      await tester.tap(find.text('Alice'));
      await tester.pump();
      expect(find.textContaining('not encrypted'), findsNothing);

      await tester.tap(find.text('Alice'));
      await tester.tap(find.text('Bob'));
      await tester.pump();
      expect(find.text('This chat is not encrypted.'), findsOneWidget);

      await tester.tap(find.text('Bob'));
      await tester.pump();
      expect(find.textContaining('not encrypted'), findsNothing);
    },
  );

  testWidgets('two unencrypted among three ticked says 2 of these chats', (
    tester,
  ) async {
    client.rooms = [
      named('!a:example.org', 'Alice'),
      named('!b:example.org', 'Bob', encrypted: false),
      named('!c:example.org', 'Cleo', encrypted: false),
    ];
    await openPicker(tester);

    await tester.tap(find.text('Alice'));
    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(find.text('1 of these chats is not encrypted.'), findsOneWidget);

    await tester.tap(find.text('Cleo'));
    await tester.pump();
    expect(find.text('2 of these chats are not encrypted.'), findsOneWidget);
  });

  testWidgets('from an unencrypted chat no note shows', (tester) async {
    client.rooms = [named('!b:example.org', 'Bob', encrypted: false)];
    await openPicker(tester, fromEncrypted: false);

    await tester.tap(find.text('Bob'));
    await tester.pump();

    expect(find.textContaining('not encrypted'), findsNothing);
    expect(sendButton(tester).onPressed, isNotNull);
  });
}
