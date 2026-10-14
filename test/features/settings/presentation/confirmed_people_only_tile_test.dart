import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/confirmed_people_only_tile.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  const description =
      'Only people you have confirmed, and your approved devices, can read '
      'what you send from this device';

  Future<ProviderContainer> pumpTile(
    WidgetTester tester, {
    required AsyncValue<AccountSecurityStatus> status,
    bool on = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings.encrypt_to_verified_sessions_only': on,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(buildTestClient()),
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountSecurityStatusProvider.overrideWithValue(status),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ConfirmedPeopleOnlyTile()),
        ),
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(ConfirmedPeopleOnlyTile)),
    );
  }

  SwitchListTile tile(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byType(SwitchListTile));

  testWidgets('turning it on shares keys only with confirmed people', (
    tester,
  ) async {
    final container = await pumpTile(
      tester,
      status: const AsyncValue.data(AccountSecurityStatus.protected),
    );

    expect(find.text('Confirmed people only'), findsOneWidget);
    expect(find.text(description), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(container.read(encryptToVerifiedSessionsOnlyProvider), isTrue);
    expect(
      container.read(matrixClientProvider).shareKeysWith,
      ShareKeysWith.directlyVerifiedOnly,
    );
  });

  testWidgets('without recovery it stays off and says what to do', (
    tester,
  ) async {
    await pumpTile(
      tester,
      status: const AsyncValue.data(AccountSecurityStatus.noRecovery),
    );

    expect(tile(tester).onChanged, isNull);
    expect(find.text('Set up recovery to turn this on'), findsOneWidget);
  });

  testWidgets('on a device not yet approved it stays off and says so', (
    tester,
  ) async {
    await pumpTile(
      tester,
      status: const AsyncValue.data(AccountSecurityStatus.deviceLocked),
    );

    expect(tile(tester).onChanged, isNull);
    expect(find.text('Approve this device to turn this on'), findsOneWidget);
  });

  testWidgets('cannot be turned on before the status is known', (tester) async {
    await pumpTile(tester, status: const AsyncValue.loading());

    expect(tile(tester).onChanged, isNull);
    expect(find.text(description), findsOneWidget);
  });

  testWidgets('once on, it can always be turned off', (tester) async {
    final container = await pumpTile(
      tester,
      status: const AsyncValue.data(AccountSecurityStatus.deviceLocked),
      on: true,
    );

    expect(tile(tester).value, isTrue);
    expect(find.text(description), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(container.read(encryptToVerifiedSessionsOnlyProvider), isFalse);
    expect(
      container.read(matrixClientProvider).shareKeysWith,
      ShareKeysWith.crossVerifiedIfEnabled,
    );
  });
}
