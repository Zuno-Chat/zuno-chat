import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_matrix.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  return container;
}

void main() {
  group('themeModeProvider', () {
    test('defaults to system when nothing is stored', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('reads a previously-stored value', () async {
      final container = await _containerWith({'settings.theme_mode': 'dark'});
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test(
      'falls back to system for a corrupt/unrecognized stored value',
      () async {
        final container = await _containerWith({
          'settings.theme_mode': 'not_a_real_mode',
        });
        addTearDown(container.dispose);
        expect(container.read(themeModeProvider), ThemeMode.system);
      },
    );

    test('set() updates state and persists it', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('settings.theme_mode'), 'light');
    });
  });

  group('notificationDeliveryModeProvider', () {
    test('defaults to fcm when nothing is stored', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.fcm,
      );
    });

    test('honours a stored choice rather than the new default', () async {
      final container = await _containerWith({
        'settings.notification_delivery_mode': 'unifiedPush',
      });
      addTearDown(container.dispose);
      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.unifiedPush,
      );
    });

    test('reads a stored fcm value as-is — no longer coerced away', () async {
      final container = await _containerWith({
        'settings.notification_delivery_mode': 'fcm',
      });
      addTearDown(container.dispose);
      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.fcm,
      );
    });

    test('set() persists fcm as-is', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      await container
          .read(notificationDeliveryModeProvider.notifier)
          .set(NotificationDeliveryMode.fcm);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('settings.notification_delivery_mode'), 'fcm');
    });

    test('falls back to fcm for a corrupt/unrecognized stored value', () async {
      final container = await _containerWith({
        'settings.notification_delivery_mode': 'not_a_real_mode',
      });
      addTearDown(container.dispose);
      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.fcm,
      );
    });

    test('reads an explicitly stored backgroundService value as-is', () async {
      final container = await _containerWith({
        'settings.notification_delivery_mode': 'backgroundService',
      });
      addTearDown(container.dispose);
      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.backgroundService,
      );
    });

    test('set() persists backgroundService', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      await container
          .read(notificationDeliveryModeProvider.notifier)
          .set(NotificationDeliveryMode.backgroundService);
      final prefs = container.read(sharedPreferencesProvider);
      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'backgroundService',
      );
    });

    test('round-trips every mode with no coercion left', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);

      for (final mode in NotificationDeliveryMode.values) {
        await container
            .read(notificationDeliveryModeProvider.notifier)
            .set(mode);
        expect(container.read(notificationDeliveryModeProvider), mode);
      }
    });
  });

  group('notifyMeProvider', () {
    test('defaults to all when nothing is stored', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      expect(container.read(notifyMeProvider), NotifyMe.all);
    });

    test('reads a previously-stored mentionsOnly value', () async {
      final container = await _containerWith({
        'settings.notify_me': 'mentionsOnly',
      });
      addTearDown(container.dispose);
      expect(container.read(notifyMeProvider), NotifyMe.mentionsOnly);
    });

    test('falls back to all for a corrupt/unrecognized stored value', () async {
      final container = await _containerWith({
        'settings.notify_me': 'not_a_real_mode',
      });
      addTearDown(container.dispose);
      expect(container.read(notifyMeProvider), NotifyMe.all);
    });

    test('set() updates state and persists it', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      await container
          .read(notifyMeProvider.notifier)
          .set(NotifyMe.mentionsOnly);
      expect(container.read(notifyMeProvider), NotifyMe.mentionsOnly);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('settings.notify_me'), 'mentionsOnly');
    });
  });

  final boolPrefs =
      <
        String,
        ({
          bool defaultValue,
          bool Function(ProviderContainer) read,
          Future<void> Function(ProviderContainer, bool) set,
        })
      >{
        'settings.incognito_keyboard': (
          defaultValue: true,
          read: (c) => c.read(incognitoKeyboardProvider),
          set: (c, v) => c.read(incognitoKeyboardProvider.notifier).set(v),
        ),
        'settings.send_typing_indicator': (
          defaultValue: true,
          read: (c) => c.read(sendTypingIndicatorProvider),
          set: (c, v) => c.read(sendTypingIndicatorProvider.notifier).set(v),
        ),
        'settings.link_previews_enabled': (
          defaultValue: true,
          read: (c) => c.read(linkPreviewsEnabledProvider),
          set: (c, v) => c.read(linkPreviewsEnabledProvider.notifier).set(v),
        ),
        'settings.low_data_calls': (
          defaultValue: true,
          read: (c) => c.read(lowDataCallsProvider),
          set: (c, v) => c.read(lowDataCallsProvider.notifier).set(v),
        ),
        'settings.confirm_before_calling': (
          defaultValue: true,
          read: (c) => c.read(confirmBeforeCallingProvider),
          set: (c, v) => c.read(confirmBeforeCallingProvider.notifier).set(v),
        ),
        'settings.show_hidden_messages': (
          defaultValue: false,
          read: (c) => c.read(showHiddenMessagesProvider),
          set: (c, v) => c.read(showHiddenMessagesProvider.notifier).set(v),
        ),
        'settings.reduce_media_size': (
          defaultValue: true,
          read: (c) => c.read(reduceMediaSizeProvider),
          set: (c, v) => c.read(reduceMediaSizeProvider.notifier).set(v),
        ),
      };

  boolPrefs.forEach((key, spec) {
    group(key, () {
      test('defaults to ${spec.defaultValue} when unset', () async {
        final container = await _containerWith({});
        addTearDown(container.dispose);
        expect(spec.read(container), spec.defaultValue);
      });

      test('reads the opposite of the default when stored', () async {
        final container = await _containerWith({key: !spec.defaultValue});
        addTearDown(container.dispose);
        expect(spec.read(container), !spec.defaultValue);
      });

      test('set() flips and persists the value', () async {
        final container = await _containerWith({});
        addTearDown(container.dispose);
        await spec.set(container, !spec.defaultValue);
        expect(spec.read(container), !spec.defaultValue);
        final prefs = container.read(sharedPreferencesProvider);
        expect(prefs.getBool(key), !spec.defaultValue);
      });
    });
  });

  group('settings.encrypt_to_verified_sessions_only', () {
    Future<ProviderContainer> containerWithClient(
      Map<String, Object> values,
    ) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          matrixClientProvider.overrideWithValue(buildTestClient()),
        ],
      );
    }

    test('defaults to false when unset', () async {
      final container = await containerWithClient({});
      addTearDown(container.dispose);
      expect(container.read(encryptToVerifiedSessionsOnlyProvider), isFalse);
      expect(
        container.read(matrixClientProvider).shareKeysWith,
        ShareKeysWith.crossVerifiedIfEnabled,
      );
    });

    test('reads true when stored', () async {
      final container = await containerWithClient({
        'settings.encrypt_to_verified_sessions_only': true,
      });
      addTearDown(container.dispose);
      expect(container.read(encryptToVerifiedSessionsOnlyProvider), isTrue);
    });

    test(
      'set() flips and persists the value, and applies it to the live client',
      () async {
        final container = await containerWithClient({});
        addTearDown(container.dispose);
        await container
            .read(encryptToVerifiedSessionsOnlyProvider.notifier)
            .set(true);
        expect(container.read(encryptToVerifiedSessionsOnlyProvider), isTrue);
        expect(
          container.read(matrixClientProvider).shareKeysWith,
          ShareKeysWith.directlyVerifiedOnly,
        );
        final prefs = container.read(sharedPreferencesProvider);
        expect(
          prefs.getBool('settings.encrypt_to_verified_sessions_only'),
          isTrue,
        );
      },
    );

    test('set(false) restores the SDK default on the live client', () async {
      final container = await containerWithClient({
        'settings.encrypt_to_verified_sessions_only': true,
      });
      addTearDown(container.dispose);
      await container
          .read(encryptToVerifiedSessionsOnlyProvider.notifier)
          .set(false);
      expect(
        container.read(matrixClientProvider).shareKeysWith,
        ShareKeysWith.crossVerifiedIfEnabled,
      );
    });
  });

  group('shareKeysWithFor', () {
    test('true maps to directlyVerifiedOnly', () {
      expect(shareKeysWithFor(true), ShareKeysWith.directlyVerifiedOnly);
    });

    test('false maps to the SDK default, crossVerifiedIfEnabled', () {
      expect(shareKeysWithFor(false), ShareKeysWith.crossVerifiedIfEnabled);
    });
  });

  group('readEncryptToVerifiedSessionsOnly', () {
    test('defaults to false when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(readEncryptToVerifiedSessionsOnly(prefs), isFalse);
    });

    test('reads a previously-stored true value', () async {
      SharedPreferences.setMockInitialValues({
        'settings.encrypt_to_verified_sessions_only': true,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readEncryptToVerifiedSessionsOnly(prefs), isTrue);
    });
  });

  group('settings.prevent_screenshots', () {
    const channel = MethodChannel('zuno/calls');
    final calls = <MethodCall>[];
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('defaults to true when unset', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      expect(container.read(preventScreenshotsProvider), isTrue);
    });

    test('reads a previously-stored false value', () async {
      final container = await _containerWith({
        'settings.prevent_screenshots': false,
      });
      addTearDown(container.dispose);
      expect(container.read(preventScreenshotsProvider), isFalse);
    });

    test(
      'set() flips and persists the value, and calls the native channel',
      () async {
        final container = await _containerWith({});
        addTearDown(container.dispose);
        await container.read(preventScreenshotsProvider.notifier).set(false);

        expect(container.read(preventScreenshotsProvider), isFalse);
        final prefs = container.read(sharedPreferencesProvider);
        expect(prefs.getBool('settings.prevent_screenshots'), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(calls, [
          isA<MethodCall>()
              .having((c) => c.method, 'method', 'setPreventScreenshots')
              .having((c) => c.arguments, 'arguments', {'enabled': false}),
        ]);
      },
    );

    test(
      'set(true) also calls the native channel with enabled: true',
      () async {
        final container = await _containerWith({
          'settings.prevent_screenshots': false,
        });
        addTearDown(container.dispose);
        await container.read(preventScreenshotsProvider.notifier).set(true);

        await Future<void>.delayed(Duration.zero);
        expect(calls, [
          isA<MethodCall>()
              .having((c) => c.method, 'method', 'setPreventScreenshots')
              .having((c) => c.arguments, 'arguments', {'enabled': true}),
        ]);
      },
    );

    test(
      'set() does not throw when the native channel is unavailable',
      () async {
        messenger.setMockMethodCallHandler(channel, null);
        final container = await _containerWith({});
        addTearDown(container.dispose);
        await expectLater(
          container.read(preventScreenshotsProvider.notifier).set(true),
          completes,
        );
      },
    );
  });

  group('readPreventScreenshots', () {
    test('defaults to true when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(readPreventScreenshots(prefs), isTrue);
    });

    test('reads a previously-stored false value', () async {
      SharedPreferences.setMockInitialValues({
        'settings.prevent_screenshots': false,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readPreventScreenshots(prefs), isFalse);
    });
  });

  group('settings.crash_reporting', () {
    test('defaults to off', () async {
      final container = await _containerWith({});
      addTearDown(container.dispose);
      expect(container.read(crashReportingProvider), isFalse);
    });

    test('reads a previously-stored opt-in', () async {
      final container = await _containerWith({
        'settings.crash_reporting': true,
      });
      addTearDown(container.dispose);
      expect(container.read(crashReportingProvider), isTrue);
    });

    test('persists an opt-in and an opt-out', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(crashReportingProvider.notifier).set(true);
      expect(container.read(crashReportingProvider), isTrue);
      expect(prefs.getBool('settings.crash_reporting'), isTrue);

      await container.read(crashReportingProvider.notifier).set(false);
      expect(container.read(crashReportingProvider), isFalse);
      expect(prefs.getBool('settings.crash_reporting'), isFalse);
    });
  });
}
