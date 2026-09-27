import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/room_info/presentation/people_trust_tile.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  late User bob;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.membership = Membership.join;
    bob = User('@bob:example.org', membership: 'invite', room: room);
  });

  User member(String id) => User(id, membership: 'join', room: room);

  void setMemberCounts({required int joined, int invited = 0}) =>
      room.summary = RoomSummary.fromJson({
        'm.joined_member_count': joined,
        'm.invited_member_count': invited,
      });

  Future<void> pumpTile(
    WidgetTester tester, {
    required List<User>? participants,
    Map<String, UserTrustState> trust = const {
      '@bob:example.org': UserTrustState.unconfirmed,
    },
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          matrixClientProvider.overrideWithValue(client),
          for (final entry in trust.entries)
            userTrustProvider(entry.key).overrideWithValue(entry.value),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PeopleTrustTile(room: room, participants: participants),
          ),
        ),
      ),
    );
  }

  testWidgets('offers no confirmation while the invitation is unanswered', (
    tester,
  ) async {
    room.summary = RoomSummary.fromJson({
      'm.heroes': ['@bob:example.org'],
      'm.joined_member_count': 1,
      'm.invited_member_count': 1,
    });

    await pumpTile(tester, participants: [bob]);

    expect(find.text('@bob'), findsOneWidget);
    expect(find.text('You can confirm them once they join'), findsOneWidget);
    expect(find.textContaining("Confirm it's really"), findsNothing);
  });

  testWidgets('offers confirmation once they have joined', (tester) async {
    room.summary = RoomSummary.fromJson({
      'm.heroes': ['@bob:example.org'],
      'm.joined_member_count': 2,
      'm.invited_member_count': 0,
    });

    await pumpTile(tester, participants: [bob]);

    expect(find.text('Confirm it is really @bob'), findsOneWidget);
    expect(find.text('You can confirm them once they join'), findsNothing);
  });

  testWidgets('says it is loading until the members arrive', (tester) async {
    await pumpTile(tester, participants: null);

    expect(find.text('People'), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
  });

  testWidgets('shows nothing when you are alone', (tester) async {
    await pumpTile(tester, participants: [member('@me:example.org')]);

    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('a group still waiting on its invitations names nobody', (
    tester,
  ) async {
    setMemberCounts(joined: 1, invited: 2);

    await pumpTile(
      tester,
      participants: [
        bob,
        User('@cat:example.org', membership: 'invite', room: room),
      ],
    );

    expect(find.text('People'), findsOneWidget);
    expect(find.text('You can confirm them once they join'), findsOneWidget);
  });

  group('one other person', () {
    setUp(() => setMemberCounts(joined: 2));

    Future<void> pumpBob(
      WidgetTester tester,
      UserTrustState state, {
      DateTime? confirmedAt,
    }) => pumpTile(
      tester,
      participants: [member('@me:example.org'), member('@bob:example.org')],
      trust: {'@bob:example.org': state},
      stored: {
        if (confirmedAt != null)
          'security.confirmed_identity_at.@bob:example.org':
              confirmedAt.millisecondsSinceEpoch,
      },
    );

    testWidgets('without recovery there is nothing to confirm', (tester) async {
      await pumpBob(tester, UserTrustState.noIdentity);

      expect(find.text('@bob'), findsOneWidget);
      expect(
        find.text(
          'They have not set up recovery, so there is nothing to confirm yet',
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    });

    testWidgets('tapping an unconfirmed person starts confirming them', (
      tester,
    ) async {
      await pumpBob(tester, UserTrustState.unconfirmed);

      await tester.tap(find.text('Confirm it is really @bob'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery first'), findsOneWidget);
    });

    testWidgets('a confirmed person says when, and that it covers new '
        'devices', (tester) async {
      await pumpBob(
        tester,
        UserTrustState.confirmed,
        confirmedAt: DateTime(2026, 3, 5, 12),
      );

      expect(find.text('@bob is confirmed'), findsOneWidget);
      expect(
        find.text(
          'Confirmed 5 March 2026. Covers any device they add later. You '
          'will not need to do this again.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    });

    testWidgets('a confirmation from before dates were kept names no date', (
      tester,
    ) async {
      await pumpBob(tester, UserTrustState.confirmed);

      expect(
        find.text(
          'Covers any device they add later. You will not need to do this '
          'again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a confirmed person with a new device says so too', (
      tester,
    ) async {
      await pumpBob(
        tester,
        UserTrustState.confirmedWithPendingDevice,
        confirmedAt: DateTime(2026, 12, 31, 12),
      );

      expect(find.text('@bob is confirmed'), findsOneWidget);
      expect(
        find.textContaining('Confirmed 31 December 2026.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('They have a device they have not approved yet.'),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).isThreeLine, true);
    });

    testWidgets('changed security details ask to confirm again', (
      tester,
    ) async {
      await pumpBob(tester, UserTrustState.identityChanged);

      expect(find.text("@bob's security details changed"), findsOneWidget);
      expect(
        find.text('Usually a new device or a reinstall. Confirm them again.'),
        findsOneWidget,
      );

      await tester.tap(find.text("@bob's security details changed"));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery first'), findsOneWidget);
    });
  });

  group('a group', () {
    setUp(() => setMemberCounts(joined: 4));

    Future<void> pumpGroup(
      WidgetTester tester,
      Map<String, UserTrustState> trust,
    ) => pumpTile(
      tester,
      participants: [
        member('@me:example.org'),
        for (final id in trust.keys) member(id),
      ],
      trust: trust,
    );

    testWidgets('says when nobody is confirmed yet', (tester) async {
      await pumpGroup(tester, {
        '@ann:example.org': UserTrustState.unconfirmed,
        '@bob:example.org': UserTrustState.noIdentity,
      });

      expect(find.text('People'), findsOneWidget);
      expect(find.text('Nobody here is confirmed yet'), findsOneWidget);
    });

    testWidgets('counts confirmed people, new devices included', (
      tester,
    ) async {
      await pumpGroup(tester, {
        '@ann:example.org': UserTrustState.confirmed,
        '@bob:example.org': UserTrustState.confirmedWithPendingDevice,
        '@cat:example.org': UserTrustState.unconfirmed,
      });

      expect(find.text('2 of 3 confirmed'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    });

    testWidgets('one changed person is named, and tapping confirms them', (
      tester,
    ) async {
      await pumpGroup(tester, {
        '@ann:example.org': UserTrustState.confirmed,
        '@bob:example.org': UserTrustState.identityChanged,
      });

      expect(find.text("@bob's security details changed"), findsOneWidget);
      expect(find.text('Confirm them again'), findsOneWidget);

      await tester.tap(find.text("@bob's security details changed"));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery first'), findsOneWidget);
    });

    testWidgets('several changed people are counted', (tester) async {
      await pumpGroup(tester, {
        '@ann:example.org': UserTrustState.identityChanged,
        '@bob:example.org': UserTrustState.identityChanged,
        '@cat:example.org': UserTrustState.confirmed,
      });

      expect(find.text('2 people’s security details changed'), findsOneWidget);
    });
  });
}
