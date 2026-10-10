import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/sign_out_wipe.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late List<String> calls;
  late SignOutWipe wipe;

  Future<void> stopDelivery() async => calls.add('stop');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls = [];
    wipe = SignOutWipe(prefs, () async => calls.add('wipe'));
  });

  test('a signed-in device is remembered and nothing is wiped', () async {
    await wipe.onLoginState(true, stopDelivery: stopDelivery);

    expect(prefs.getBool(signedInMarkerKey), isTrue);
    expect(calls, isEmpty);
  });

  test('signing out after a session stops delivery, then wipes and forgets '
      'the session, so a launch after a wipe that kept the app running does '
      'not wipe again', () async {
    await wipe.onLoginState(true, stopDelivery: stopDelivery);

    await wipe.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, ['stop', 'wipe']);
    expect(prefs.getBool(signedInMarkerKey), isNull);
  });

  test('a session left from an earlier run is wiped at launch', () async {
    await prefs.setBool(signedInMarkerKey, true);

    await wipe.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, ['stop', 'wipe']);
  });

  test('a device that never signed in is never wiped', () async {
    await wipe.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, isEmpty);
  });

  test('a failed delivery stop does not block the wipe', () async {
    await prefs.setBool(signedInMarkerKey, true);

    await wipe.onLoginState(
      false,
      stopDelivery: () async => throw Exception('offline'),
    );

    expect(calls, ['wipe']);
  });

  test('a delivery stop that hangs is given up on, then the wipe runs', () {
    fakeAsync((async) {
      prefs.setBool(signedInMarkerKey, true);
      unawaited(
        wipe.onLoginState(false, stopDelivery: () => Completer<void>().future),
      );

      async.elapse(stopDeliveryBeforeWipeBudget - const Duration(seconds: 1));
      expect(calls, isEmpty);

      async.elapse(const Duration(seconds: 2));
      expect(calls, ['wipe']);
    });
  });

  test('repeated sign-out states wipe once', () async {
    await prefs.setBool(signedInMarkerKey, true);

    await Future.wait([
      wipe.onLoginState(false, stopDelivery: stopDelivery),
      wipe.onLoginState(false, stopDelivery: stopDelivery),
    ]);

    expect(calls.where((c) => c == 'wipe'), hasLength(1));
  });

  test(
    'signing in and out again in the same run stops delivery again',
    () async {
      await wipe.onLoginState(true, stopDelivery: stopDelivery);
      await wipe.onLoginState(false, stopDelivery: stopDelivery);

      await wipe.onLoginState(true, stopDelivery: stopDelivery);
      await wipe.onLoginState(false, stopDelivery: stopDelivery);

      expect(calls, ['stop', 'wipe', 'stop', 'wipe']);
    },
  );

  test('a refused wipe is not fatal and keeps the session marked, so the next '
      'launch tries again', () async {
    await prefs.setBool(signedInMarkerKey, true);
    final refusing = SignOutWipe(prefs, () async => throw Exception('no'));

    await refusing.onLoginState(false, stopDelivery: stopDelivery);

    expect(prefs.getBool(signedInMarkerKey), isTrue);
  });

  test('after a refused wipe, the next sign-out in the same run stops '
      'delivery and tries the wipe again', () async {
    await prefs.setBool(signedInMarkerKey, true);
    final refusing = SignOutWipe(prefs, () async {
      calls.add('wipe');
      throw Exception('no');
    });

    await refusing.onLoginState(false, stopDelivery: stopDelivery);
    await refusing.onLoginState(true, stopDelivery: stopDelivery);
    await refusing.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, ['stop', 'wipe', 'stop', 'wipe']);
  });

  group('signOutWipeProvider', () {
    const channel = MethodChannel('zuno/app_data');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add('native ${call.method}');
        return true;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    SignOutWipe providedWipe({
      PlatformCapabilities? capabilities,
      Future<void> Function()? vacuum,
      String? databasePath = '/data/Library/Application Support/zuno.db',
    }) {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseVacuumProvider.overrideWithValue(
            vacuum ?? () async => calls.add('vacuum'),
          ),
          liveDatabasePathProvider.overrideWithValue(() => databasePath),
          if (capabilities != null)
            platformCapabilitiesProvider.overrideWithValue(capabilities),
        ],
      );
      addTearDown(container.dispose);
      return container.read(signOutWipeProvider);
    }

    test('a wipe the platform declines keeps the session marked, so the next '
        'launch tries again', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      await prefs.setBool(signedInMarkerKey, true);

      await providedWipe().onLoginState(false, stopDelivery: stopDelivery);

      expect(prefs.getBool(signedInMarkerKey), isTrue);
    });

    test('without a native wipe, signing out still stops delivery and never '
        'calls native', () async {
      await prefs.setBool(signedInMarkerKey, true);

      await providedWipe(
        capabilities: capabilitiesLike(
          iosCapabilities,
          nativeSignOutWipe: false,
        ),
      ).onLoginState(false, stopDelivery: stopDelivery);

      expect(calls, ['stop']);
    });

    group('where the wipe leaves the app running', () {
      final keepsProcess = iosCapabilities;

      test('the emptied database is vacuumed before the native wipe, and the '
          'preferences are read back afterwards', () async {
        await prefs.setBool(signedInMarkerKey, true);
        await prefs.setString('theme', 'dark');
        Object? arguments;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add('native ${call.method}');
          arguments = call.arguments;
          SharedPreferences.setMockInitialValues({});
          return true;
        });

        await providedWipe(capabilities: keepsProcess)
            .onLoginState(false, stopDelivery: stopDelivery);

        expect(calls, ['stop', 'vacuum', 'native wipe']);
        expect(arguments, {
          'keep': ['/data/Library/Application Support/zuno.db'],
        });
        expect(prefs.getString('theme'), isNull);
        expect(prefs.getBool(signedInMarkerKey), isNull);
      });

      test('without the open database\'s path nothing is wiped, so the '
          'database can never be deleted from under the app', () async {
        await prefs.setBool(signedInMarkerKey, true);

        await providedWipe(
          capabilities: keepsProcess,
          databasePath: null,
        ).onLoginState(false, stopDelivery: stopDelivery);

        expect(calls, ['stop', 'vacuum']);
        expect(prefs.getBool(signedInMarkerKey), isTrue);
      });

      test('a vacuum that fails does not stop the wipe', () async {
        await prefs.setBool(signedInMarkerKey, true);

        await providedWipe(
          capabilities: keepsProcess,
          vacuum: () async => throw StateError('locked'),
        ).onLoginState(false, stopDelivery: stopDelivery);

        expect(calls, ['stop', 'native wipe']);
        expect(prefs.getBool(signedInMarkerKey), isNull);
      });

      test('a wipe the platform declines keeps the session marked', () async {
        messenger.setMockMethodCallHandler(channel, (call) async => false);
        await prefs.setBool(signedInMarkerKey, true);

        await providedWipe(capabilities: keepsProcess)
            .onLoginState(false, stopDelivery: stopDelivery);

        expect(prefs.getBool(signedInMarkerKey), isTrue);
      });
    });

    test('where the platform ends the app, signing out wipes through the '
        'native side with no arguments, and nothing is vacuumed', () async {
      Object? arguments = 'unset';
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add('native ${call.method}');
        arguments = call.arguments;
        return true;
      });
      await prefs.setBool(signedInMarkerKey, true);

      await providedWipe(capabilities: androidCapabilities)
          .onLoginState(false, stopDelivery: stopDelivery);

      expect(calls, ['stop', 'native wipe']);
      expect(arguments, isNull);
    });
  });
}
