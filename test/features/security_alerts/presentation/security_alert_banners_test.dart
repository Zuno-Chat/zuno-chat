import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/alerts/security_alert.dart';
import 'package:zuno/core/security/alerts/security_alerts_provider.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/alert_banner.dart';
import 'package:zuno/features/security_alerts/presentation/security_alert_banners.dart';

import '../../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _carol = '@carol:example.org';

class _Alerts extends SecurityAlertsNotifier {
  final List<RecordedSecurityAlert> initial;

  _Alerts(this.initial);

  @override
  List<RecordedSecurityAlert> build() => initial;
}

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: _me);
    room = buildTestRoom(client);
    client.rooms.add(room);
    for (final (id, membership) in [
      (_me, 'join'),
      (_bob, 'join'),
      (_carol, 'invite'),
    ]) {
      room.setState(User(id, membership: membership, room: room));
    }
  });

  Future<void> pump(
    WidgetTester tester,
    Widget banners, {
    List<RecordedSecurityAlert> recorded = const [],
    Map<String, UserTrustState> trust = const {},
    AccountSecurityStatus? status,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          securityAlertsProvider.overrideWith(() => _Alerts(recorded)),
          userTrustProvider.overrideWith(
            (ref, userId) => trust[userId] ?? UserTrustState.confirmed,
          ),
          if (status != null)
            accountSecurityStatusProvider.overrideWithValue(AsyncData(status)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: banners),
        ),
      ),
    );
  }

  group('on the chat list', () {
    testWidgets('nothing to alert about renders nothing', (tester) async {
      await pump(tester, const SecurityAlertBanners.account());

      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('names the device that just signed in, with one button', (
      tester,
    ) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        recorded: const [
          NewSignInAlert(deviceId: 'BBB', displayName: 'Pixel 8a'),
        ],
      );

      expect(find.text('New sign-in'), findsOneWidget);
      expect(find.textContaining('Pixel 8a'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review'), findsOneWidget);
    });

    for (final (count, more) in [
      (2, '+1 more new sign-in'),
      (3, '+2 more new sign-ins'),
    ]) {
      testWidgets('$count open sign-ins say $more', (tester) async {
        await pump(
          tester,
          const SecurityAlertBanners.account(),
          recorded: [
            for (var i = 0; i < count; i++) NewSignInAlert(deviceId: 'DEV$i'),
          ],
        );

        expect(find.text(more), findsOneWidget);
      });
    }

    testWidgets('dismissing drops only the shown sign-in', (tester) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        recorded: const [
          NewSignInAlert(deviceId: 'BBB', displayName: 'First'),
          NewSignInAlert(deviceId: 'CCC', displayName: 'Second'),
        ],
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.textContaining('Second'), findsOneWidget);
      expect(find.textContaining('First'), findsNothing);
    });

    testWidgets('a replaced recovery code leads, with one button', (
      tester,
    ) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        recorded: const [
          NewSignInAlert(deviceId: 'BBB'),
          RecoveryResetAlert('NEW'),
        ],
      );

      final titles = tester
          .widgetList<AlertBanner>(find.byType(AlertBanner))
          .map((banner) => banner.title);
      expect(titles, [
        'Your recovery code was replaced on another device',
        'New sign-in',
      ]);
      expect(find.textContaining('change your password'), findsOneWidget);
    });

    testWidgets('a sign-in shows where and when it was seen', (tester) async {
      final seenAt = DateTime.now();
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        recorded: [
          NewSignInAlert(
            deviceId: 'BBB',
            displayName: 'Pixel 8a',
            ipAddress: '81.2.69.160',
            seenAt: seenAt,
          ),
        ],
      );

      expect(find.textContaining('Today at '), findsOneWidget);
      expect(find.textContaining(' · 81.2.69.160'), findsOneWidget);
    });

    testWidgets('an account problem shows its Settings card button', (
      tester,
    ) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        status: AccountSecurityStatus.recoveryStale,
      );

      expect(find.text('This device has an old recovery code'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Enter code'), findsOneWidget);
    });

    testWidgets('closing a sign-in does not bring it back as a waiting '
        'device', (tester) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        recorded: const [NewSignInAlert(deviceId: 'BBB')],
        status: AccountSecurityStatus.deviceWaiting,
      );
      expect(find.text('New sign-in'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('dismissing an account problem hides it', (tester) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        status: AccountSecurityStatus.deviceLocked,
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('a person-level alert never shows there', (tester) async {
      await pump(
        tester,
        const SecurityAlertBanners.account(),
        recorded: const [
          UnvouchedDeviceAlert(userId: _bob, deviceIds: {'B2'}),
        ],
        trust: const {_bob: UserTrustState.identityChanged},
      );

      expect(find.byType(AlertBanner), findsNothing);
    });
  });

  group('in a chat', () {
    testWidgets('says nothing while everyone is as confirmed', (tester) async {
      await pump(tester, SecurityAlertBanners.room(room));

      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('names the one person whose details changed', (tester) async {
      await pump(
        tester,
        SecurityAlertBanners.room(room),
        trust: const {_bob: UserTrustState.identityChanged},
      );

      expect(find.text("@bob's security details changed"), findsOneWidget);
      expect(find.textContaining('someone is listening in'), findsOneWidget);
      expect(find.byTooltip('Dismiss'), findsNothing);
    });

    testWidgets('counts several, invited people included', (tester) async {
      await pump(
        tester,
        SecurityAlertBanners.room(room),
        trust: const {
          _bob: UserTrustState.identityChanged,
          _carol: UserTrustState.identityChanged,
        },
      );

      expect(find.text("2 people's security details changed"), findsOneWidget);
    });

    testWidgets('Confirm starts confirming that person', (tester) async {
      await pump(
        tester,
        SecurityAlertBanners.room(room),
        trust: const {_bob: UserTrustState.identityChanged},
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery first'), findsOneWidget);
    });

    testWidgets('warns about a new device someone cannot vouch for', (
      tester,
    ) async {
      await pump(
        tester,
        SecurityAlertBanners.room(room),
        recorded: const [
          UnvouchedDeviceAlert(userId: _bob, deviceIds: {'B2'}),
        ],
      );

      expect(find.text('@bob signed in on a new device'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('shows an identity change and a new device together', (
      tester,
    ) async {
      await pump(
        tester,
        SecurityAlertBanners.room(room),
        recorded: const [
          UnvouchedDeviceAlert(userId: _bob, deviceIds: {'B2'}),
        ],
        trust: const {_carol: UserTrustState.identityChanged},
      );

      expect(find.byType(AlertBanner), findsNWidgets(2));
    });
  });
}
