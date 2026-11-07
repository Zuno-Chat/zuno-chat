import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/core/settings/matrix_experience.dart';
import 'package:zuno/features/room_info/presentation/member_actions.dart';
import 'package:zuno/features/room_info/presentation/person_sheet.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/route_launcher.dart';

void main() {
  late Client client;
  late Room room;
  late List<http.Request> requests;
  late List<String> inCommon;

  setUp(() {
    requests = [];
    inCommon = [];
    client = buildTestClient(
      userId: '@me:example.org',
      database: CachingFakeDatabaseApi(),
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/versions')) {
          return http.Response(
            jsonEncode({
              'versions': ['v1.19'],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/mutual_rooms')) {
          return http.Response(
            jsonEncode({'joined': inCommon, 'count': inCommon.length}),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = namedRoom(client, '!walks:example.org', 'Walks');
    client.rooms.add(room);
  });

  User member(String id, String name, {String membership = 'join'}) {
    final user = User(
      id,
      membership: membership,
      displayName: name,
      room: room,
    );
    room.setState(user);
    return user;
  }

  void setLevels(Map<String, int> users) =>
      setPowerLevels(room, {'users': users});

  Iterable<http.Request> mutualRoomRequests() =>
      requests.where((r) => r.url.path.endsWith('/mutual_rooms'));

  MemberAction? chosen;

  Future<void> show(
    WidgetTester tester,
    User user, {
    Map<String, UserTrustState> trust = const {},
    Map<String, Object> stored = const {},
    List<String>? unblocked,
    bool matrixExperience = false,
  }) async {
    chosen = null;
    final container = await containerWithPreferences(
      stored,
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        userTrustProvider.overrideWith(
          (ref, id) => trust[id] ?? UserTrustState.unconfirmed,
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              MatrixExperience(on: matrixExperience, child: child!),
          home: Scaffold(
            body: routeLauncher<void>(
              (_) => Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () async => chosen = await openPersonSheet(
                      context,
                      ref,
                      room: room,
                      user: user,
                      unblockPerson: (id) async => unblocked?.add(id),
                    ),
                    child: const Text('show person'),
                  ),
                ),
              ),
              label: 'open chat',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('show person'));
    await tester.pumpAndSettle();
  }

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(BottomSheet), matching: finder);

  testWidgets('shows their picture, name, username and role, the quick '
      'actions and, to an admin, moderation', (tester) async {
    setLevels({'@me:example.org': 100, '@ann:example.org': 50});
    await show(tester, member('@ann:example.org', 'Ann'));

    for (final text in [
      'Ann',
      '@ann',
      'Moderator',
      'Message',
      'Block',
      'Report',
      'Change role',
      'Remove from room',
      'Ban from room',
    ]) {
      expect(inSheet(find.text(text)), findsOneWidget, reason: text);
    }
    expect(inSheet(find.textContaining('example.org')), findsNothing);
  });

  testWidgets('with the Matrix experience on, the username keeps its server', (
    tester,
  ) async {
    await show(
      tester,
      member('@ann:example.org', 'Ann'),
      matrixExperience: true,
    );

    expect(inSheet(find.text('@ann:example.org')), findsOneWidget);
    expect(inSheet(find.text('@ann')), findsNothing);
  });

  testWidgets('a chosen action closes the sheet and is acted on', (
    tester,
  ) async {
    setLevels({'@me:example.org': 100});
    await show(tester, member('@ann:example.org', 'Ann'));

    await tester.tap(inSheet(find.text('Remove from room')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Remove Ann?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(chosen, MemberAction.remove);
    expect(requests.where((r) => r.url.path.endsWith('/kick')), hasLength(1));
  });

  testWidgets('shows Confirmed with the date, only once you confirmed them', (
    tester,
  ) async {
    await show(
      tester,
      member('@ann:example.org', 'Ann'),
      trust: {'@ann:example.org': UserTrustState.confirmed},
      stored: {
        'security.confirmed_identity_at.@ann:example.org': DateTime(
          2026,
          3,
          5,
          12,
        ).millisecondsSinceEpoch,
      },
    );

    expect(inSheet(find.text('Confirmed')), findsOneWidget);
    expect(inSheet(find.text('March 5, 2026')), findsOneWidget);
  });

  testWidgets('says nothing about trust for someone not confirmed', (
    tester,
  ) async {
    await show(
      tester,
      member('@ann:example.org', 'Ann'),
      trust: {'@ann:example.org': UserTrustState.identityChanged},
    );

    expect(inSheet(find.text('Confirmed')), findsNothing);
  });

  testWidgets('lists the other rooms you share once you expand the row', (
    tester,
  ) async {
    client.rooms.add(namedRoom(client, '!climb:example.org', 'Climbing club'));
    inCommon = ['!walks:example.org', '!climb:example.org'];
    await show(tester, member('@ann:example.org', 'Ann'));

    expect(inSheet(find.text('1 room in common')), findsOneWidget);
    expect(inSheet(find.text('Climbing club')), findsNothing);

    await tester.tap(inSheet(find.text('1 room in common')));
    await tester.pumpAndSettle();

    expect(inSheet(find.text('Climbing club')), findsOneWidget);
  });

  testWidgets('no rooms in common row when you share no other room', (
    tester,
  ) async {
    inCommon = ['!walks:example.org'];
    await show(tester, member('@ann:example.org', 'Ann'));

    expect(mutualRoomRequests(), hasLength(1));
    expect(inSheet(find.textContaining('in common')), findsNothing);
  });

  testWidgets('a person you blocked shows Blocked and offers Unblock, which '
      'returns to the chat list', (tester) async {
    setBlocked(client, ['@ann:example.org']);
    final unblocked = <String>[];
    await show(tester, member('@ann:example.org', 'Ann'), unblocked: unblocked);

    expect(inSheet(find.text('Blocked')), findsOneWidget);
    expect(inSheet(find.text('Block')), findsNothing);

    await tester.tap(inSheet(find.text('Unblock')));
    await tester.pumpAndSettle();
    expect(find.text('Unblock Ann?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Unblock'));
    await tester.pumpAndSettle();

    expect(unblocked, ['@ann:example.org']);
    expect(find.text('show person'), findsNothing);
    expect(find.text('open chat'), findsOneWidget);
    expect(find.text('Ann unblocked'), findsOneWidget);
  });
}
