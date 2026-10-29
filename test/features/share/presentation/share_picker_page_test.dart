import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/optimistic_room_state.dart';
import 'package:zuno/features/share/presentation/share_picker_page.dart';
import 'package:zuno/features/share/presentation/share_target_list.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
  });

  List<String> targetIds(List<Room> rooms) => [
    for (final target in shareTargets(rooms, englishLocalizations))
      target.room.id,
  ];

  group('shareTargets', () {
    test('keeps joined rooms in the given order and drops the rest', () {
      final rooms = [
        namedRoom(client, '!b:example.org', 'Bob'),
        namedRoom(
          client,
          '!i:example.org',
          'Invite',
          membership: Membership.invite,
        ),
        namedRoom(client, '!a:example.org', 'Alice'),
        namedRoom(
          client,
          '!l:example.org',
          'Left',
          membership: Membership.leave,
        ),
      ];
      expect(targetIds(rooms), ['!b:example.org', '!a:example.org']);
    });

    test('drops communities, which hold no messages', () {
      final community = namedRoom(client, '!c:example.org', 'Climbing club');
      applyOptimisticRoomState(community, EventTypes.RoomCreate, {
        'type': 'm.space',
      });
      final rooms = [community, namedRoom(client, '!a:example.org', 'Alice')];

      expect(targetIds(rooms), ['!a:example.org']);
    });

    test('drops rooms the user cannot post in', () {
      final announcements = namedRoom(
        client,
        '!r:example.org',
        'Announcements',
      );
      applyOptimisticRoomState(announcements, EventTypes.RoomPowerLevels, {
        'events_default': 50,
        'users': {'@admin:example.org': 100},
      });
      final rooms = [
        announcements,
        namedRoom(client, '!a:example.org', 'Alice'),
      ];

      expect(targetIds(rooms), ['!a:example.org']);
    });

    test('drops a direct chat the other person left', () {
      final left = namedRoom(client, '!d:example.org', 'Bob');
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': ['!d:example.org'],
        },
      );
      applyOptimisticRoomState(left, EventTypes.RoomMember, {
        'membership': 'leave',
      }, stateKey: '@bob:example.org');
      left.summary
        ..mJoinedMemberCount = 1
        ..mInvitedMemberCount = 0;
      final rooms = [left, namedRoom(client, '!a:example.org', 'Alice')];

      expect(targetIds(rooms), ['!a:example.org']);
    });

    test('a chat in a community carries that community', () {
      final crew = namedRoom(client, '!crew:example.org', 'Belay crew');
      final club = namedRoom(client, '!club:example.org', 'Climbing club');
      applyOptimisticRoomState(club, EventTypes.RoomCreate, {
        'type': 'm.space',
      });
      applyOptimisticRoomState(club, EventTypes.SpaceChild, {
        'via': ['example.org'],
      }, stateKey: crew.id);
      applyOptimisticRoomState(crew, EventTypes.SpaceParent, {
        'via': ['example.org'],
      }, stateKey: club.id);
      final other = namedRoom(client, '!other:example.org', 'Book club');

      final targets = shareTargets([crew, other, club], englishLocalizations);

      expect(targets.map((t) => t.community?.name), ['Climbing club', null]);
    });

    test('a half-linked chat carries no community', () {
      final crew = namedRoom(client, '!crew:example.org', 'Belay crew');
      final club = namedRoom(client, '!club:example.org', 'Climbing club');
      applyOptimisticRoomState(club, EventTypes.RoomCreate, {
        'type': 'm.space',
      });
      applyOptimisticRoomState(club, EventTypes.SpaceChild, {
        'via': ['example.org'],
      }, stateKey: crew.id);

      final targets = shareTargets([crew, club], englishLocalizations);

      expect(targets.single.community, isNull);
    });
  });

  group('matchingShareTargets', () {
    List<String> matching(List<Room> rooms, String query) => [
      for (final target in matchingShareTargets(
        shareTargets(rooms, englishLocalizations),
        query,
      ))
        target.room.id,
    ];

    test('matches the display name case-insensitively', () {
      final rooms = [
        namedRoom(client, '!a:example.org', 'Alice'),
        namedRoom(client, '!b:example.org', 'Bob'),
      ];
      expect(matching(rooms, ' aLi '), ['!a:example.org']);
      expect(matching(rooms, 'zzz'), isEmpty);
    });

    test('an empty search keeps every target', () {
      final rooms = [
        namedRoom(client, '!a:example.org', 'Alice'),
        namedRoom(client, '!b:example.org', 'Bob'),
      ];
      expect(matching(rooms, '  '), ['!a:example.org', '!b:example.org']);
    });

    test('matches the name shown, such as whom a new chat waits on', () {
      final waiting = buildTestRoom(client, id: '!w:example.org')
        ..membership = Membership.join;
      applyOptimisticRoomState(waiting, EventTypes.RoomMember, {
        'membership': 'join',
      }, stateKey: '@me:example.org');
      applyOptimisticRoomState(waiting, EventTypes.RoomMember, {
        'membership': 'invite',
        'displayname': 'Zed Smith',
      }, stateKey: '@zed:example.org');
      final target = shareTargets([waiting], englishLocalizations).single;

      expect(target.title, '@zed');
      expect(matching([waiting], '@zed'), ['!w:example.org']);
      expect(matching([waiting], 'smith'), isEmpty);
    });
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SharePickerPage(
          client: client,
          destination: (room) => Scaffold(body: Text('picked ${room.id}')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tapping a chat replaces the picker with the destination', (
    tester,
  ) async {
    client.rooms = [
      namedRoom(client, '!a:example.org', 'Alice'),
      namedRoom(client, '!b:example.org', 'Bob'),
    ];
    await pumpPicker(tester);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text('picked !b:example.org'), findsOneWidget);
    expect(find.byType(SharePickerPage), findsNothing);
  });

  testWidgets('searching narrows the list', (tester) async {
    client.rooms = [
      namedRoom(client, '!a:example.org', 'Alice'),
      namedRoom(client, '!b:example.org', 'Bob'),
    ];
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'bo');
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('no matches shows a calm empty line', (tester) async {
    client.rooms = [namedRoom(client, '!a:example.org', 'Alice')];
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pump();

    expect(find.text('No chats found'), findsOneWidget);
  });
}
