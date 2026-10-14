import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/app_language.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/locale');
  late List<MethodCall> calls;
  Object? getReply;

  setUp(() {
    calls = [];
    getReply = {'supported': true, 'tag': null};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'get' ? getReply : null;
        });
    ambientCapabilities = androidCapabilities;
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  group('parseAppLanguage', () {
    test('an unsupported device reads as null', () {
      expect(parseAppLanguage({'supported': false}), isNull);
    });

    test('a missing reply reads as null', () {
      expect(parseAppLanguage(null), isNull);
    });

    test('no tag means the device language', () {
      expect(parseAppLanguage({'supported': true, 'tag': null})!.tag, isNull);
    });

    test('an empty tag means the device language', () {
      expect(parseAppLanguage({'supported': true, 'tag': ''})!.tag, isNull);
    });

    test('a tag is kept', () {
      expect(parseAppLanguage({'supported': true, 'tag': 'el'})!.tag, 'el');
    });
  });

  group('AppLanguage.locale', () {
    test('matches a supported locale by language code', () {
      expect(const AppLanguage('el-GR').locale?.languageCode, 'el');
    });

    test('is null for the device language', () {
      expect(const AppLanguage(null).locale, isNull);
    });

    test('is null for a language Zuno does not ship', () {
      expect(const AppLanguage('fr').locale, isNull);
    });
  });

  group('appLanguageProvider', () {
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('reads the current choice', () async {
      getReply = {'supported': true, 'tag': 'el'};
      final c = container();

      expect((await c.read(appLanguageProvider.future))!.tag, 'el');
    });

    test('is null and never touches the channel on iOS', () async {
      ambientCapabilities = iosCapabilities;
      final c = container();

      expect(await c.read(appLanguageProvider.future), isNull);
      expect(calls, isEmpty);
    });

    test('is null below Android 13', () async {
      getReply = {'supported': false};
      final c = container();

      expect(await c.read(appLanguageProvider.future), isNull);
    });

    test('a failing channel reads as null, not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'boom');
          });
      final c = container();

      expect(await c.read(appLanguageProvider.future), isNull);
    });

    test('setting sends the tag and refreshes the state', () async {
      final c = container();
      await c.read(appLanguageProvider.future);
      getReply = {'supported': true, 'tag': 'el'};

      await c.read(appLanguageProvider.notifier).set('el');

      expect(calls.map((call) => call.method), ['get', 'set', 'get']);
      expect(calls[1].arguments, {'tag': 'el'});
      expect(c.read(appLanguageProvider).value!.tag, 'el');
    });

    test('choosing the device language sends a null tag', () async {
      getReply = {'supported': true, 'tag': 'el'};
      final c = container();
      await c.read(appLanguageProvider.future);
      getReply = {'supported': true, 'tag': null};

      await c.read(appLanguageProvider.notifier).set(null);

      expect(calls[1].arguments, {'tag': null});
      expect(c.read(appLanguageProvider).value!.tag, isNull);
    });
  });
}
