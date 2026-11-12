import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/features/settings/presentation/sign_out_tile.dart';

import '../../../helpers/fake_call_session.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';

class _SigningOutClient extends Client {
  _SigningOutClient() : super('test', database: FakeDatabaseApi()) {
    setUserId('@alex:example.org');
  }

  final journal = <String>[];

  @override
  Future<void> logout() async => journal.add('logged out');
}

Future<void> _pumpTile(
  WidgetTester tester, {
  required AccountSecurityStatus status,
  Client? client,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(
          client ?? buildTestClient(userId: '@alex:example.org'),
        ),
        accountSecurityStatusProvider.overrideWithValue(
          AsyncValue.data(status),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ListView(children: const [SignOutTile()])),
      ),
    ),
  );
}

void main() {
  testWidgets('logging out asks first', (tester) async {
    await _pumpTile(tester, status: AccountSecurityStatus.protected);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Set up recovery'), findsNothing);
    expect(
      find.textContaining(
        'erases everything it stored on this device and '
        'closes',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an account with no recovery is told what it will lose', (
    tester,
  ) async {
    await _pumpTile(tester, status: AccountSecurityStatus.noRecovery);

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
    await _pumpTile(tester, status: AccountSecurityStatus.noRecovery);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    final anyway = tester.getCenter(find.text('Sign out anyway')).dy;
    final recovery = tester.getCenter(find.text('Set up recovery')).dy;
    final cancel = tester.getCenter(find.text('Cancel')).dy;
    expect(anyway, lessThan(recovery));
    expect(recovery, lessThan(cancel));
  });

  testWidgets('signing out mid-call ends the call before the token goes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    silenceMethodChannels(const ['zuno/background_sync']);
    final client = _SigningOutClient();
    await _pumpTile(
      tester,
      status: AccountSecurityStatus.protected,
      client: client,
    );
    ProviderScope.containerOf(tester.element(find.byType(SignOutTile)))
        .read(activeCallProvider.notifier)
        .set(
          FakeCallSession(
            room: buildCallRoom(),
            kind: CallKind.voice,
            journal: client.journal,
          ),
        );

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out').last);
    await tester.pumpAndSettle();

    expect(client.journal, ['call ended', 'logged out']);
  });

  testWidgets('cancelling leaves the account alone', (tester) async {
    final client = _SigningOutClient();
    await _pumpTile(
      tester,
      status: AccountSecurityStatus.protected,
      client: client,
    );

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsNothing);
    expect(client.journal, isEmpty);
  });
}
