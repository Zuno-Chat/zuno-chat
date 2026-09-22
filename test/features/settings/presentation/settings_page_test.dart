import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/features/settings/presentation/settings_page.dart';

import '../../../helpers/fake_matrix.dart';

class _OwnMemberDb extends FakeDatabaseApi {
  User? ownMember;

  @override
  Future<User?> getUser(String userId, Room room) async =>
      ownMember?.id == userId ? ownMember : null;
}

Client _client() {
  final client = buildTestClient(userId: '@alex:example.org');
  final room = buildTestRoom(client)..partial = false;
  room.setState(
    User(
      '@alex:example.org',
      membership: 'join',
      displayName: 'Alex Doe',
      room: room,
    ),
  );
  client.rooms.add(room);
  return client;
}

Future<void> _pumpSettingsPage(
  WidgetTester tester, {
  AccountSecurityStatus? status,
  bool? showFeedback,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(_client()),
        if (status != null)
          accountSecurityStatusProvider.overrideWithValue(
            AsyncValue.data(status),
          ),
      ],
      child: MaterialApp(
        home: showFeedback == null
            ? const SettingsPage()
            : SettingsPage(showFeedback: showFeedback),
      ),
    ),
  );
}

void main() {
  testWidgets('shows every settings category', (tester) async {
    await _pumpSettingsPage(tester);

    for (final category in [
      'Notifications',
      'Chats & calls',
      'Data & storage',
      'Security',
      'About',
    ]) {
      expect(find.text(category), findsOneWidget);
    }
  });

  testWidgets('you are on top: name, username, and a way into Account', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text('Alex Doe'), findsOneWidget);
    expect(find.text('alex · Profile, password'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alex Doe')).dy,
      lessThan(tester.getTopLeft(find.text('Notifications')).dy),
    );
  });

  testWidgets('a rename shows on the card without reopening Settings', (
    tester,
  ) async {
    final client = _client();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    expect(find.text('Alex Doe'), findsOneWidget);

    final room = client.rooms.first;
    room.setState(
      User(
        '@alex:example.org',
        membership: 'join',
        displayName: 'Alexandra',
        room: room,
      ),
    );
    client.onRoomState.add((
      roomId: room.id,
      state: room.getState(EventTypes.RoomMember, '@alex:example.org')!,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Alexandra'), findsOneWidget);
  });

  testWidgets('on a cold start the name comes from the local store', (
    tester,
  ) async {
    final db = _OwnMemberDb();
    final client = buildTestClient(userId: '@alex:example.org', database: db);
    final room = buildTestRoom(client);
    client.rooms.add(room);
    db.ownMember = User(
      '@alex:example.org',
      membership: 'join',
      displayName: 'Alex From Disk',
      room: room,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Alex From Disk'), findsOneWidget);
  });

  testWidgets('the last card clears the system navigation bar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(_client())],
        child: const MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
          child: MaterialApp(home: SettingsPage()),
        ),
      ),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    expect((list.padding! as EdgeInsets).bottom, 16 + 48);
  });

  testWidgets('settings sit in four cards, leaving last', (tester) async {
    await _pumpSettingsPage(tester);

    expect(find.byType(CardGroup), findsNWidgets(4));
    final leaving = find.byType(CardGroup).last;
    expect(
      find.descendant(of: leaving, matching: find.text('Sign out')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: leaving, matching: find.text('Delete account')),
      findsOneWidget,
    );
  });

  testWidgets('the thin categories it replaced are gone', (tester) async {
    await _pumpSettingsPage(tester);

    expect(find.text('General'), findsNothing);
    expect(find.text('App preferences'), findsNothing);
    expect(find.text('Voice & video'), findsNothing);
  });

  testWidgets('destructive actions stay on the root screen', (tester) async {
    await _pumpSettingsPage(tester);

    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('no server-admin badge or Homeserver information entry', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text("You're a homeserver admin"), findsNothing);
    expect(find.text('Homeserver information'), findsNothing);
  });

  testWidgets('logging out asks first', (tester) async {
    await _pumpSettingsPage(tester, status: AccountSecurityStatus.protected);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Set up recovery'), findsNothing);
  });

  testWidgets('an account with no recovery is told what it will lose', (
    tester,
  ) async {
    await _pumpSettingsPage(tester, status: AccountSecurityStatus.noRecovery);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.textContaining('gone for good'), findsOneWidget);
    expect(find.text('Set up recovery'), findsOneWidget);
    expect(find.text('Sign out anyway'), findsOneWidget);
  });

  testWidgets('when the sign-out choices stack, the action comes first and '
      'Cancel last', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await _pumpSettingsPage(tester, status: AccountSecurityStatus.noRecovery);

    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    final anyway = tester.getCenter(find.text('Sign out anyway')).dy;
    final recovery = tester.getCenter(find.text('Set up recovery')).dy;
    final cancel = tester.getCenter(find.text('Cancel')).dy;
    expect(anyway, lessThan(recovery));
    expect(recovery, lessThan(cancel));
  });

  testWidgets('cancelling leaves the account alone', (tester) async {
    await _pumpSettingsPage(tester, status: AccountSecurityStatus.protected);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsNothing);
  });

  testWidgets('Send feedback opens the feedback sheet', (tester) async {
    await _pumpSettingsPage(tester, showFeedback: true);

    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Your feedback'), findsOneWidget);
  });

  testWidgets('no Send feedback in a build with nowhere to send it', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text('Send feedback'), findsNothing);
  });
}
