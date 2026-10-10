import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/room_info/presentation/room_permissions_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/pump_until.dart';

void main() {
  late Room room;
  late List<http.Request> requests;
  late bool refuse;

  setUp(() {
    requests = [];
    refuse = false;
    final client = buildTestClient(
      userId: '@me:example.org',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (refuse) {
          return http.Response('{"errcode":"M_FORBIDDEN","error":"x"}', 403);
        }
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  void setOwnLevel(int level) {
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomPowerLevels,
        senderId: '@owner:example.org',
        stateKey: '',
        content: {
          'users': {'@owner:example.org': 100, '@me:example.org': level},
        },
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: RoomPermissionsPage(room: room)));
    await tester.pump();
  }

  ListTile row(WidgetTester tester, String title) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, title));

  testWidgets('every permission sits on a card', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('an admin can change a permission and sees no notice', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expect(row(tester, 'Change room name').onTap, isNotNull);
    expect(find.textContaining('Only admins can change these'), findsNothing);
  });

  testWidgets('a moderator only views, and is told why', (tester) async {
    setOwnLevel(50);
    await pumpPage(tester);

    expect(row(tester, 'Change room name').onTap, isNull);
    expect(row(tester, 'Default role for new members').onTap, isNull);
    expect(
      find.text('Only admins can change these. You can view them here.'),
      findsOneWidget,
    );
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('the notice goes away when dismissed', (tester) async {
    setOwnLevel(50);
    await pumpPage(tester);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(find.textContaining('Only admins can change these'), findsNothing);
    expect(find.text('Change room name'), findsOneWidget);
  });

  Future<void> network(WidgetTester tester) async {
    await pumpRealAsync(tester, rounds: 3);
    await tester.pumpAndSettle();
  }

  Map<String, Object?> sentLevels() =>
      jsonDecode(requests.single.body) as Map<String, Object?>;

  String? roleOf(WidgetTester tester, String title) => tester
      .widget<Text>(
        find
            .descendant(
              of: find.widgetWithText(ListTile, title),
              matching: find.byType(Text),
            )
            .last,
      )
      .data;

  testWidgets('the role picker lists every role, highest first, with the '
      'current one ticked', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    await tester.tap(find.text('Change room name'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    final labels = tester
        .widgetList<ListTile>(
          find.descendant(of: sheet, matching: find.byType(ListTile)),
        )
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(labels, ['Admin', 'Moderator', 'Member', 'Read-only']);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Moderator').last,
        matching: find.byIcon(Icons.check_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an admin picks a new role and it is saved and shown', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    await tester.tap(find.text('Change room name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await network(tester);

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.pathSegments, contains('m.room.power_levels'));
    expect(sentLevels()['events'], {EventTypes.RoomName: 100});
    expect(
      (sentLevels()['users'] as Map)['@me:example.org'],
      100,
      reason: 'the rest of the power levels are kept',
    );
    expect(roleOf(tester, 'Change room name'), 'Admin');
  });

  testWidgets('the default role for new members can be changed', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expect(roleOf(tester, 'Default role for new members'), 'Member');
    await tester.tap(find.text('Default role for new members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read-only').last);
    await network(tester);

    expect(sentLevels()['users_default'], -1);
    expect(roleOf(tester, 'Default role for new members'), 'Read-only');
  });

  testWidgets('picking the current role, or nothing, saves nothing', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    await tester.tap(find.text('Invite people'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member').last);
    await network(tester);

    await tester.tap(find.text('Invite people'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await network(tester);

    expect(requests, isEmpty);
  });

  testWidgets('a refused change keeps the old role and says so', (
    tester,
  ) async {
    setOwnLevel(100);
    refuse = true;
    await pumpPage(tester);

    await tester.tap(find.text('Remove people'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await network(tester);

    expect(requests, hasLength(1));
    expect(find.text('Not saved. Try again.'), findsOneWidget);
    expect(roleOf(tester, 'Remove people'), 'Moderator');
  });

  group('a community', () {
    setUp(() {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomCreate,
          senderId: '@owner:example.org',
          stateKey: '',
          content: {'type': 'm.space'},
        ),
      );
    });

    testWidgets('shows its own rules and none a community lacks', (
      tester,
    ) async {
      setOwnLevel(100);
      await pumpPage(tester);

      expect(find.text('Community defaults'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Rooms'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Add rooms'), findsOneWidget);
      expect(find.text('Change description'), findsOneWidget);
      expect(find.text('Send messages'), findsNothing);
      expect(find.text('Start or join calls'), findsNothing);
      expect(find.text('Turn on encryption'), findsNothing);
      expectEveryRowOnACard();
    });
  });
}
