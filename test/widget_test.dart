import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/app.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/security/device_safety.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

import 'helpers/fake_matrix.dart';
import 'helpers/fixed_homeserver.dart';

Future<SharedPreferences> _mockPreferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  final signedOutOnZuno = [
    homeserverProvider.overrideWith(() => FixedHomeserver(officialHomeserver)),
    registrationSupportProvider.overrideWith(
      (ref) async =>
          const RegistrationSupport(RegistrationAvailability.disabled),
    ),
  ];

  testWidgets('shows the sign-in screen when logged out', (tester) async {
    final preferences = await _mockPreferences();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(const AsyncValue.data(false)),
          sharedPreferencesProvider.overrideWithValue(preferences),
          deviceRisksProvider.overrideWithValue(
            const AsyncValue.data(<DeviceRisk>{}),
          ),
          matrixClientProvider.overrideWithValue(buildTestClient()),
          ...signedOutOnZuno,
        ],
        child: const ZunoApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('zuno.chat'), findsOneWidget);
  });

  testWidgets('shows the ink brand mark on amber, not a bare spinner, while '
      'login state is still resolving', (tester) async {
    final preferences = await _mockPreferences();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(const AsyncValue.loading()),
          sharedPreferencesProvider.overrideWithValue(preferences),
          deviceRisksProvider.overrideWithValue(
            const AsyncValue.data(<DeviceRisk>{}),
          ),
        ],
        child: const ZunoApp(),
      ),
    );
    await tester.pump();

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = picture.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/logo/zuno-mark-ink.svg');
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, zunoAmber);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('uses the Zuno themes, not the Flutter default', (tester) async {
    final preferences = await _mockPreferences();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(const AsyncValue.data(false)),
          sharedPreferencesProvider.overrideWithValue(preferences),
          deviceRisksProvider.overrideWithValue(
            const AsyncValue.data(<DeviceRisk>{}),
          ),
          matrixClientProvider.overrideWithValue(buildTestClient()),
          ...signedOutOnZuno,
        ],
        child: const ZunoApp(),
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme, same(zunoLightTheme));
    expect(materialApp.darkTheme, same(zunoDarkTheme));
    expect(materialApp.theme!.colorScheme.primaryContainer, zunoAmber);
  });

  Future<void> pumpWithConnection(
    WidgetTester tester,
    ConnectionStatus status,
  ) async {
    final preferences = await _mockPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(const AsyncValue.data(false)),
          sharedPreferencesProvider.overrideWithValue(preferences),
          deviceRisksProvider.overrideWithValue(
            const AsyncValue.data(<DeviceRisk>{}),
          ),
          matrixClientProvider.overrideWithValue(buildTestClient()),
          ...signedOutOnZuno,
          connectionStatusProvider.overrideWithValue(AsyncData(status)),
        ],
        child: const ZunoApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets('no banner while online', (tester) async {
    await pumpWithConnection(tester, ConnectionStatus.online);

    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('says the internet is gone when the device has no network', (
    tester,
  ) async {
    await pumpWithConnection(tester, ConnectionStatus.noInternet);

    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('does not blame the internet when the network is up but '
      'nothing answers', (tester) async {
    await pumpWithConnection(tester, ConnectionStatus.unreachable);

    expect(
      find.text('Cannot connect right now. Trying again…'),
      findsOneWidget,
    );
    expect(find.text('No internet connection'), findsNothing);
  });
}
