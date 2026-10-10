import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/settings/presentation/delete_account_tile.dart';

import '../../../helpers/fake_call_session.dart';
import '../../../helpers/fake_live_location.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/uia_challenge.dart';

class _DeactivatingClient extends Client {
  _DeactivatingClient(this.journal)
    : super('test', database: FakeDatabaseApi()) {
    setUserId('@alice:example.org');
  }

  final passwords = <String>[];
  final erasures = <bool?>[];
  final clears = <SessionClearReason>[];
  final refusals = <Object>[];
  final List<String> journal;

  @override
  Future<IdServerUnbindResult> deactivateAccount({
    AuthenticationData? auth,
    bool? erase,
    String? idServer,
  }) async {
    if (auth == null) throw uiaPasswordChallenge();
    passwords.add((auth as AuthenticationPassword).password);
    if (refusals.isNotEmpty) throw refusals.removeAt(0);
    journal.add('deactivated');
    erasures.add(erase);
    return IdServerUnbindResult.success;
  }

  @override
  Future<void> clear({
    SessionClearReason reason = SessionClearReason.unspecified,
  }) async => clears.add(reason);
}

LiveLocationSharing _sharing(Client client) => LiveLocationSharing(
  client: client,
  capture: FakeLiveLocationCapture(),
  isOffline: () => false,
  recipients: (_) async => const <DeviceKeys>[],
);

void answer(WidgetTester tester, FakeCallSession call) =>
    ProviderScope.containerOf(tester.element(find.byType(DeleteAccountTile)))
        .read(activeCallProvider.notifier)
        .set(call);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Client? client,
    FakeCallSession? activeCall,
    LiveLocationSharing? sharing,
  }) async {
    final liveLocation = sharing ?? _sharing(LiveLocationTestClient());
    addTearDown(liveLocation.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (client != null) matrixClientProvider.overrideWithValue(client),
          liveLocationSharingProvider.overrideWithValue(liveLocation),
        ],
        child: MaterialApp(
          home: Scaffold(body: ListView(children: const [DeleteAccountTile()])),
        ),
      ),
    );
    if (activeCall != null) answer(tester, activeCall);
  }

  testWidgets('tapping warns before anything else', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('nobody can undo this'), findsOneWidget);
    expect(
      find.textContaining('erases everything it stored on this device'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('cancelling the warning leaves the account alone', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  group('type-to-confirm', () {
    testWidgets('shows the username, not the full Matrix ID', (tester) async {
      await pump(tester, client: buildTestClient(userId: '@alice:example.org'));

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Type your username to confirm: alice'), findsOneWidget);
      expect(find.textContaining('@alice:example.org'), findsNothing);
      expect(find.textContaining('example.org'), findsNothing);
    });

    testWidgets(
      'Delete account stays disabled until the username matches exactly',
      (tester) async {
        await pump(
          tester,
          client: buildTestClient(userId: '@alice:example.org'),
        );

        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        Finder deleteButton() =>
            find.widgetWithText(TextButton, 'Delete account');

        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'alic');
        await tester.pump();
        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), '@alice:example.org');
        await tester.pump();
        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'alice');
        await tester.pump();
        expect(tester.widget<TextButton>(deleteButton()).onPressed, isNotNull);
      },
    );

    testWidgets('cancelling here leaves the account alone too', (tester) async {
      await pump(tester, client: buildTestClient(userId: '@alice:example.org'));

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });
  });

  testWidgets('a username typed with a trailing space still matches', (
    tester,
  ) async {
    await pump(tester, client: buildTestClient(userId: '@alice:example.org'));

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'alice ');
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Delete account'))
          .onPressed,
      isNotNull,
    );
  });

  group('after the username matches', () {
    late LiveLocationTestClient sharingClient;
    late LiveLocationSharing sharing;
    late _DeactivatingClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sharingClient = LiveLocationTestClient();
      sharingClient.rooms.add(
        LiveLocationTestRoom(id: '!family:x', client: sharingClient),
      );
      sharing = _sharing(sharingClient);
      client = _DeactivatingClient(sharingClient.journal);
      silenceMethodChannels(const ['zuno/background_sync']);
    });

    FakeCallSession call() => FakeCallSession(
      room: buildCallRoom(),
      kind: CallKind.voice,
      journal: client.journal,
    );

    Future<void> share() => sharing.start(
      sharingClient.getRoomById('!family:x')!,
      LiveLocationDuration.hour,
      LivePosition(
        geo: const GeoUri(latitude: 1, longitude: 2),
        at: DateTime.now(),
      ),
    );

    Future<void> reachPassword(
      WidgetTester tester, {
      FakeCallSession? activeCall,
    }) async {
      await pump(
        tester,
        client: client,
        activeCall: activeCall,
        sharing: sharing,
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle();
    }

    Future<void> enterPassword(WidgetTester tester, String password) async {
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('asks for the password, erases the account, then clears '
        'this device', (tester) async {
      await reachPassword(tester);

      expect(
        find.text('Confirm your password to delete your account'),
        findsOneWidget,
      );

      await enterPassword(tester, 'hunter2');
      await finish(tester);

      expect(client.passwords, ['hunter2']);
      expect(client.erasures, [true]);
      expect(client.clears, [SessionClearReason.logout]);
    });

    testWidgets('a call in progress ends once the password is in, before '
        'the account goes', (tester) async {
      await reachPassword(tester, activeCall: call());
      expect(client.journal, isEmpty);

      await enterPassword(tester, 'hunter2');
      await finish(tester);

      expect(client.journal, ['call ended', 'deactivated']);
    });

    testWidgets('a call answered while the password prompt is open still '
        'ends before the account goes', (tester) async {
      await reachPassword(tester);
      answer(tester, call());

      await enterPassword(tester, 'hunter2');
      await finish(tester);

      expect(client.journal, ['call ended', 'deactivated']);
    });

    testWidgets('a live share stops once the password is in, before the '
        'account goes', (tester) async {
      await tester.runAsync(share);
      await reachPassword(tester);

      await enterPassword(tester, 'hunter2');
      await finish(tester);

      expect(client.journal, [
        'share published',
        'share cleared',
        'deactivated',
      ]);
    });

    testWidgets('cancelling the password leaves the call and the share alone', (
      tester,
    ) async {
      await tester.runAsync(share);
      await reachPassword(tester, activeCall: call());

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await finish(tester);

      expect(client.journal, ['share published']);
      expect(sharing.shares.value, isNotEmpty);
    });

    for (final (name, inCall, sharingNow, notice) in [
      (
        'the password prompt says what confirming ends, and only while '
            'something is live',
        true,
        true,
        'Confirming ends your call and stops sharing your location, even '
            'if the password is wrong.',
      ),
      (
        'with only a call, the prompt names only the call',
        true,
        false,
        'Confirming ends your call, even if the password is wrong.',
      ),
      (
        'with only a share, the prompt names only the share',
        false,
        true,
        'Confirming stops sharing your location, even if the password is '
            'wrong.',
      ),
    ]) {
      testWidgets(name, (tester) async {
        if (sharingNow) await tester.runAsync(share);
        await reachPassword(tester, activeCall: inCall ? call() : null);

        expect(find.text(notice), findsOneWidget);
      });
    }

    testWidgets('with nothing live, the prompt asks only for the password', (
      tester,
    ) async {
      await reachPassword(tester);

      expect(find.textContaining('Confirming'), findsNothing);
    });

    testWidgets('a wrong password has already ended the call, but Cancel then '
        'keeps the account', (tester) async {
      client.refusals.add(uiaPasswordChallenge(errcode: 'M_FORBIDDEN'));
      await reachPassword(tester, activeCall: call());

      await enterPassword(tester, 'wrong');
      expect(find.text('Wrong password.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await finish(tester);

      expect(client.journal, ['call ended']);
      expect(client.clears, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('cancelling the password deletes nothing, quietly', (
      tester,
    ) async {
      await reachPassword(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(client.passwords, isEmpty);
      expect(client.clears, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('no connection says so', (tester) async {
      client.refusals.add(const SocketException('offline'));
      await reachPassword(tester);

      await enterPassword(tester, 'hunter2');

      expect(
        find.text('Cannot connect. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(client.clears, isEmpty);
    });

    testWidgets('once done, it stops answering password prompts', (
      tester,
    ) async {
      await reachPassword(tester);
      await enterPassword(tester, 'hunter2');
      await finish(tester);

      client.onUiaRequest.add(
        UiaRequest(request: (auth) async => throw uiaPasswordChallenge()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
