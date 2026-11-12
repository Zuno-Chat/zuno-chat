import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:zuno/core/errors/crash_reporting.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/matrix_experience.dart';
import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/features/settings/presentation/settings_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

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
  bool showFeedback = false,
  PlatformCapabilities? capabilities,
  bool matrixExperience = false,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(_client()),
        sentryConfiguredProvider.overrideWithValue(showFeedback),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            MatrixExperience(on: matrixExperience, child: child!),
        home: const SettingsPage(),
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

  testWidgets('on Android the categories name screenshots, delivery and '
      'donate', (tester) async {
    await _pumpSettingsPage(tester, capabilities: androidCapabilities);

    expect(find.text('Recovery, devices, screenshots'), findsOneWidget);
    expect(find.text('Sounds, delivery'), findsOneWidget);
    expect(find.text('Version, donate, diagnostics'), findsOneWidget);
  });

  testWidgets('on iOS the categories name screen content, mentions and terms, '
      'never screenshots, delivery or donate', (tester) async {
    await _pumpSettingsPage(tester, capabilities: iosCapabilities);

    expect(find.text('Recovery, devices, screen content'), findsOneWidget);
    expect(find.text('Sounds, mentions'), findsOneWidget);
    expect(find.text('Version, terms, diagnostics'), findsOneWidget);
    for (final word in ['screenshots', 'delivery', 'donate']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('you are on top: name, username, and a way into Account', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text('Alex Doe'), findsOneWidget);
    expect(find.text('@alex · Profile, password'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alex Doe')).dy,
      lessThan(tester.getTopLeft(find.text('Notifications')).dy),
    );
  });

  testWidgets('with the Matrix experience on, your username keeps its '
      'server', (tester) async {
    await _pumpSettingsPage(tester, matrixExperience: true);

    expect(find.text('@alex:example.org · Profile, password'), findsOneWidget);
  });

  testWidgets('a rename shows on the card without reopening Settings', (
    tester,
  ) async {
    final client = _client();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
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
        overrides: [
          matrixClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Alex From Disk'), findsOneWidget);
  });

  testWidgets('settings sit in three cards, with no way to leave here', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.byType(CardGroup), findsNWidgets(3));
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
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
