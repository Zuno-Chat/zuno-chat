import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/blocking/presentation/blocked_people_page.dart';
import 'package:zuno/features/settings/presentation/active_sessions_page.dart';
import 'package:zuno/features/settings/presentation/advanced_security_page.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';
import 'package:zuno/features/settings/presentation/security_privacy_settings_page.dart';
import 'package:zuno/features/settings/presentation/why_security_page.dart';
import 'package:zuno/features/verification/presentation/approve_this_device_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

class _NoDevicesClient extends EncryptedTestClient {
  _NoDevicesClient() : super(userId: '@me:example.org', testDeviceId: 'HERE');

  @override
  Future<List<Device>?> getDevices() async => [];

  @override
  Future<void> updateUserDeviceKeys({Set<String>? additionalUsers}) async {}
}

AccountSecurityFacts _factsFor(AccountSecurityStatus status) =>
    AccountSecurityFacts(
      recoveryExists: status != AccountSecurityStatus.noRecovery,
      thisDeviceHasIdentityKeys: status != AccountSecurityStatus.deviceLocked,
      keyBackupExists: true,
      keyBackupUsableHere: status != AccountSecurityStatus.recoveryStale,
      unapprovedOtherDevices: status == AccountSecurityStatus.deviceWaiting
          ? 1
          : 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const callsChannel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(callsChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(callsChannel, null));

  Finder switchTile(String title) =>
      find.widgetWithText(SwitchListTile, title, skipOffstage: false);

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    PlatformCapabilities? capabilities,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    final client = buildTestClient(userId: '@me:example.org');
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          if (capabilities != null)
            platformCapabilitiesProvider.overrideWithValue(capabilities),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: SecurityPrivacySettingsPage());
          },
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('Blocked people opens the list of blocked people', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Blocked people'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockedPeoplePage), findsOneWidget);
    expect(find.text('Nobody is blocked'), findsOneWidget);
  });

  testWidgets('App lock no longer appears anywhere on the page', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('App lock'), findsNothing);
  });

  testWidgets('Prevent screenshots is a real, enabled toggle — on by default', (
    tester,
  ) async {
    await pumpPage(tester);

    final tile = tester.widget<SwitchListTile>(
      switchTile('Prevent screenshots'),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);
    expect(
      tile.subtitle,
      isNot(isA<Text>().having((t) => t.data, 'data', 'Coming soon')),
    );
  });

  group('where the platform cannot block screenshots', () {
    testWidgets('there is no Prevent screenshots toggle', (tester) async {
      await pumpPage(
        tester,
        capabilities: capabilitiesLike(
          androidCapabilities,
          screenSecurity: false,
        ),
      );

      expect(switchTile('Prevent screenshots'), findsNothing);
      expect(
        find.textContaining('recent apps preview', skipOffstage: false),
        findsNothing,
      );
      expect(switchTile('Incognito keyboard'), findsOneWidget);
    });
  });

  group('where screen content can be hidden but screenshots not blocked', () {
    testWidgets('the toggle says what it hides, and that screenshots still '
        'work', (tester) async {
      await pumpPage(tester, capabilities: iosCapabilities);

      expect(switchTile('Prevent screenshots'), findsNothing);
      final tile = tester.widget<SwitchListTile>(
        switchTile('Hide screen content'),
      );
      expect(tile.value, isTrue);
      expect(
        find.text(
          'Hides Zuno in the app switcher and while the screen is recorded '
          'or shared. Screenshots still work.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('recent apps preview', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('it turns the same setting off through the same channel', (
      tester,
    ) async {
      final container = await pumpPage(tester, capabilities: iosCapabilities);

      await tester.tap(switchTile('Hide screen content'));
      await tester.pump();

      expect(container.read(preventScreenshotsProvider), isFalse);
      expect(
        calls,
        contains(
          isA<MethodCall>()
              .having((c) => c.method, 'method', 'setPreventScreenshots')
              .having((c) => c.arguments, 'arguments', {'enabled': false}),
        ),
      );
    });
  });

  testWidgets('iOS keeps the On this device group for the screen, without '
      'the keyboard it cannot ask not to learn', (tester) async {
    await pumpPage(tester, capabilities: iosCapabilities);

    expect(switchTile('Incognito keyboard'), findsNothing);
    expect(find.text('On this device', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Android keeps the toggle', (tester) async {
    await pumpPage(tester, capabilities: androidCapabilities);

    expect(switchTile('Prevent screenshots'), findsOneWidget);
  });

  testWidgets('reads a previously-stored false value as off', (tester) async {
    await pumpPage(tester, prefs: {'settings.prevent_screenshots': false});

    final tile = tester.widget<SwitchListTile>(
      switchTile('Prevent screenshots'),
    );
    expect(tile.value, isFalse);
  });

  testWidgets('tapping the toggle flips it, persists it, and calls the native '
      'FLAG_SECURE channel', (tester) async {
    final container = await pumpPage(tester);

    await tester.tap(switchTile('Prevent screenshots'));
    await tester.pump();

    expect(container.read(preventScreenshotsProvider), isFalse);
    final tile = tester.widget<SwitchListTile>(
      switchTile('Prevent screenshots'),
    );
    expect(tile.value, isFalse);

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool('settings.prevent_screenshots'), isFalse);

    expect(
      calls,
      contains(
        isA<MethodCall>()
            .having((c) => c.method, 'method', 'setPreventScreenshots')
            .having((c) => c.arguments, 'arguments', {'enabled': false}),
      ),
    );
  });

  testWidgets(
    'tapping it while off turns it back on and calls the channel with true',
    (tester) async {
      final container = await pumpPage(
        tester,
        prefs: {'settings.prevent_screenshots': false},
      );

      await tester.tap(switchTile('Prevent screenshots'));
      await tester.pump();

      expect(container.read(preventScreenshotsProvider), isTrue);
      expect(
        calls,
        contains(
          isA<MethodCall>()
              .having((c) => c.method, 'method', 'setPreventScreenshots')
              .having((c) => c.arguments, 'arguments', {'enabled': true}),
        ),
      );
    },
  );

  testWidgets(
    "the row's subtitle discloses the recent-apps-thumbnail side effect",
    (tester) async {
      await pumpPage(tester);
      expect(
        find.textContaining('recent apps preview', skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('Incognito keyboard is a real toggle — on by default', (
    tester,
  ) async {
    final container = await pumpPage(tester);
    final tile = tester.widget<SwitchListTile>(
      switchTile('Incognito keyboard'),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);

    await tester.tap(switchTile('Incognito keyboard'));
    await tester.pump();

    expect(container.read(incognitoKeyboardProvider), isFalse);
  });

  testWidgets('Send crash reports moved out, to About', (tester) async {
    await pumpPage(tester);

    expect(find.text('Send crash reports', skipOffstage: false), findsNothing);
  });

  testWidgets('Advanced is a disabled placeholder that opens nothing', (
    tester,
  ) async {
    await pumpPage(tester);

    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Advanced', skipOffstage: false),
    );
    expect(row.enabled, isFalse);

    await tester.tap(find.text('Advanced'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(AdvancedSecurityPage), findsNothing);
  });

  group('leaving for another page', () {
    late int factReads;

    Future<void> pumpWithStatus(
      WidgetTester tester,
      AccountSecurityStatus status,
    ) async {
      factReads = 0;
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final sharedPrefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matrixClientProvider.overrideWithValue(_NoDevicesClient()),
            sharedPreferencesProvider.overrideWithValue(sharedPrefs),
            accountSecurityFactsProvider.overrideWith((ref) {
              factReads++;
              return Stream.value(_factsFor(status));
            }),
          ],
          child: const MaterialApp(home: SecurityPrivacySettingsPage()),
        ),
      );
      await tester.pump();
    }

    Future<void> open(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> comeBack(WidgetTester tester) async {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }

    Finder action(String label) => find.widgetWithText(FilledButton, label);

    testWidgets('without recovery the card sets it up from scratch', (
      tester,
    ) async {
      await pumpWithStatus(tester, AccountSecurityStatus.noRecovery);

      await open(tester, action('Set up recovery'));

      final page = tester.widget<SecureBackupPage>(
        find.byType(SecureBackupPage),
      );
      expect(page.autoRestoreExisting, isNull);
    });

    testWidgets('a locked device is sent to approval', (tester) async {
      await pumpWithStatus(tester, AccountSecurityStatus.deviceLocked);

      await open(tester, action('Unlock them'));

      expect(find.byType(ApproveThisDevicePage), findsOneWidget);
    });

    testWidgets('a waiting sign-in is reviewed among the devices', (
      tester,
    ) async {
      await pumpWithStatus(tester, AccountSecurityStatus.deviceWaiting);

      await open(tester, action('Review'));

      expect(find.byType(ActiveSessionsPage), findsOneWidget);
    });

    testWidgets('an old recovery code goes straight to entering the new one', (
      tester,
    ) async {
      await pumpWithStatus(tester, AccountSecurityStatus.recoveryStale);

      await open(tester, action('Enter code'));

      final page = tester.widget<SecureBackupPage>(
        find.byType(SecureBackupPage),
      );
      expect(page.autoRestoreExisting, isTrue);
    });

    testWidgets('a protected account has nothing to act on', (tester) async {
      await pumpWithStatus(tester, AccountSecurityStatus.protected);

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the recovery row offers a change once recovery exists', (
      tester,
    ) async {
      await pumpWithStatus(tester, AccountSecurityStatus.protected);

      expect(find.text('Change your recovery code'), findsOneWidget);
      expect(find.textContaining('need approving again'), findsOneWidget);

      await open(tester, find.text('Change your recovery code'));

      expect(find.byType(SecureBackupPage), findsOneWidget);
    });

    testWidgets('the recovery row offers a setup without it', (tester) async {
      await pumpWithStatus(tester, AccountSecurityStatus.noRecovery);

      expect(find.widgetWithText(ListTile, 'Set up recovery'), findsOneWidget);
      expect(find.text('Change your recovery code'), findsNothing);
    });

    testWidgets('Your devices lists the devices', (tester) async {
      await pumpWithStatus(tester, AccountSecurityStatus.protected);

      await open(tester, find.text('Your devices'));

      expect(find.byType(ActiveSessionsPage), findsOneWidget);
    });

    testWidgets('How this works explains it', (tester) async {
      await pumpWithStatus(tester, AccountSecurityStatus.protected);

      await open(tester, find.text('How this works'));

      expect(find.byType(WhySecurityPage), findsOneWidget);
    });

    testWidgets('coming back checks the status again', (tester) async {
      await pumpWithStatus(tester, AccountSecurityStatus.protected);
      expect(factReads, 1);

      await open(tester, find.text('How this works'));
      await comeBack(tester);

      expect(find.byType(WhySecurityPage), findsNothing);
      expect(factReads, 2);
    });
  });
}
