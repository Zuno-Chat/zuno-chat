import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/l10n/native_strings.dart';

Map<String, Object?> _catalogLocalizations(
  Map<String, String> out,
  String key,
) {
  final catalog = jsonDecode(
    out['ios/Shared/Localizable.xcstrings']!,
  ) as Map<String, Object?>;
  final strings = catalog['strings']! as Map<String, Object?>;
  return (strings[key]! as Map<String, Object?>)['localizations']!
      as Map<String, Object?>;
}

const _plist = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>NSCameraUsageDescription</key>
\t<string>old</string>
</dict>
</plist>
''';

Directory _repo(Map<String, String> arbs) {
  final root = Directory.systemTemp.createTempSync('native_strings');
  for (final MapEntry(:key, :value) in arbs.entries) {
    File('${root.path}/lib/l10n/$key')
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  for (final target in ['Runner', 'NotificationService', 'ShareExtension']) {
    File('${root.path}/ios/$target/Info.plist')
      ..createSync(recursive: true)
      ..writeAsStringSync(_plist);
  }
  addTearDown(() => root.deleteSync(recursive: true));
  return root;
}

void _expectRejected(Map<String, String> arbs, List<String> mentions) {
  final repo = _repo(arbs);
  expect(
    () => buildOutputs(repo),
    throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        allOf([for (final m in mentions) contains(m)]),
      ),
    ),
  );
}

void main() {
  test(
    'escapes special characters for Android and keeps them literal on iOS',
    () {
      final out = buildOutputs(
        _repo({
          'app_en.arb': r'''{
  "@@locale": "en",
  "tricky": "@Don't \"quote\" 100% & <tags>\nnext…",
  "@tricky": {"x-native": ["app", "ios"]}
}''',
        }),
      );
      expect(
        out['android/app/src/main/res/values/strings_l10n.xml'],
        contains(
          r'''<string name="tricky">\@Don\'t \"quote\" 100% &amp; &lt;tags&gt;\nnext…</string>''',
        ),
      );
      expect(
        out['ios/Shared/Localizable.xcstrings'],
        contains(r'''"value" : "@Don't \"quote\" 100% & <tags>\nnext…"'''),
      );
    },
  );

  test('positional placeholders on both platforms and a typed Swift accessor', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb': '''{
  "@@locale": "en",
  "invite": "{name} invited you to {count} rooms, 100%",
  "@invite": {"x-native": ["app", "ios"], "placeholders": {"name": {"type": "String"}, "count": {"type": "int"}}}
}''',
      }),
    );
    expect(
      out['android/app/src/main/res/values/strings_l10n.xml'],
      contains(
        r'<string name="invite">%1$s invited you to %2$d rooms, 100%%</string>',
      ),
    );
    expect(
      out['ios/Shared/Localizable.xcstrings'],
      contains(r'"value" : "%1$@ invited you to %2$lld rooms, 100%%"'),
    );
    expect(
      out['ios/Shared/L10n.swift'],
      contains('static func invite(_ name: String, _ count: Int) -> String'),
    );
  });

  test('a whole-message plural becomes Android plurals and iOS variations', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb': '''{
  "@@locale": "en",
  "moreChats": "{count, plural, one{New messages in {count} more chat} other{New messages in {count} more chats}}",
  "@moreChats": {"x-native": ["ios", "zuno_notifications"], "placeholders": {"count": {"type": "int"}}}
}''',
      }),
    );
    final android =
        out['packages/zuno_notifications/android/src/main/res/values/strings_l10n.xml']!;
    expect(android, contains('<plurals name="moreChats">'));
    expect(
      android,
      contains(r'<item quantity="one">New messages in %1$d more chat</item>'),
    );
    final ios = out['ios/Shared/Localizable.xcstrings']!;
    expect(ios, contains('"plural" : {'));
    expect(ios, contains(r'"value" : "New messages in %1$lld more chats"'));
    expect(
      out['ios/Shared/L10n.swift'],
      contains(
        'String.localizedStringWithFormat(L10n.text("moreChats"), count)',
      ),
    );
  });

  test('a translation keeps the plural cases its language needs, few and '
      'many included', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb': '''{
  "@@locale": "en",
  "moreChats": "{count, plural, one{{count} more chat} other{{count} more chats}}",
  "@moreChats": {"x-native": ["ios", "zuno_notifications"], "placeholders": {"count": {"type": "int"}}}
}''',
        'app_pl.arb': '{"@@locale": "pl", "moreChats": "{count, plural, one{{count} czat} few{{count} czaty} many{{count} czatów} other{{count} czatów}}"}',
      }),
    );
    final android =
        out['packages/zuno_notifications/android/src/main/res/values-pl/strings_l10n.xml']!;
    expect(android, contains(r'<item quantity="few">%1$d czaty</item>'));
    expect(android, contains(r'<item quantity="many">%1$d czatów</item>'));
    final polish =
        _catalogLocalizations(out, 'moreChats')['pl']! as Map<String, Object?>;
    final variations = polish['variations']! as Map<String, Object?>;
    final plural = variations['plural']! as Map<String, Object?>;
    expect(plural.keys, unorderedEquals(['one', 'few', 'many', 'other']));
  });

  test(
    'an untranslated key falls back to English instead of an empty string',
    () {
      final out = buildOutputs(
        _repo({
          'app_en.arb': '''{
  "@@locale": "en",
  "hangUp": "Hang up",
  "@hangUp": {"x-native": ["app", "ios"]},
  "ongoing": "Ongoing call",
  "@ongoing": {"x-native": ["app", "ios"]}
}''',
          'app_de.arb': '''{
  "@@locale": "de",
  "hangUp": "Auflegen"
}''',
        }),
      );
      final german =
          out['android/app/src/main/res/values-de/strings_l10n.xml']!;
      expect(german, contains('Auflegen'));
      expect(german, isNot(contains('ongoing')));
      expect(_catalogLocalizations(out, 'hangUp'), contains('de'));
      expect(_catalogLocalizations(out, 'ongoing'), isNot(contains('de')));
      final swift = out['ios/Shared/L10n.swift']!;
      expect(
        swift,
        contains('Bundle.main.path(forResource: "en", ofType: "lproj")'),
      );
      expect(swift, contains('localized == missing ? english.localizedString'));
    },
  );

  test('locale qualifiers and language lists', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb':
            '{"@@locale": "en", "k": "K", "@k": {"x-native": ["app"]}}',
        'app_pt.arb': '{"@@locale": "pt", "@@x-region": "PT", "k": "K"}',
        'app_pt_BR.arb': '{"@@locale": "pt_BR", "k": "K"}',
        'app_zh_Hant.arb': '{"@@locale": "zh_Hant", "k": "K"}',
      }),
    );
    expect(
      out,
      contains('android/app/src/main/res/values-pt-rBR/strings_l10n.xml'),
    );
    expect(
      out,
      contains('android/app/src/main/res/values-b+zh+Hant/strings_l10n.xml'),
    );
    expect(
      out['android/app/src/main/res/xml/locales_config.xml'],
      contains('<locale android:name="pt-BR"/>'),
    );
    expect(out['ios/Runner/Info.plist'], contains('<string>zh-Hant</string>'));
  });

  test('Info.plist usage text comes from the ARB, XML-escaped', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb': '''{
  "@@locale": "en",
  "cameraUse": "Zuno uses the camera for calls & codes.",
  "@cameraUse": {"x-ios-infoplist": ["NSCameraUsageDescription"]}
}''',
      }),
    );
    expect(
      out['ios/Runner/Info.plist'],
      contains('<string>Zuno uses the camera for calls &amp; codes.</string>'),
    );
    expect(
      out['ios/Runner/InfoPlist.xcstrings'],
      contains('"NSCameraUsageDescription"'),
    );
    expect(
      out['ios/NotificationService/Info.plist'],
      contains('<key>CFBundleLocalizations</key>'),
    );
  });

  test('unsupported message shapes fail loudly, naming the key', () {
    _expectRejected(
      {
        'app_en.arb': '''{
  "@@locale": "en",
  "pick": "{kind, select, a{A} other{B}}",
  "@pick": {"x-native": ["ios"]}
}''',
      },
      ['pick'],
    );
  });

  test(
    'a plural selector that is not a declared int fails, naming the key',
    () {
      _expectRejected(
        {
          'app_en.arb': '''{
  "@@locale": "en",
  "chats": "{count, plural, one{{count} chat} other{{count} chats}}",
  "@chats": {"x-native": ["ios"], "placeholders": {"count": {"type": "String"}}}
}''',
        },
        ['chats', 'count'],
      );
      _expectRejected(
        {
          'app_en.arb': '''{
  "@@locale": "en",
  "chats": "{count, plural, one{One chat} other{Many chats}}",
  "@chats": {"x-native": ["ios"]}
}''',
        },
        ['chats', 'count'],
      );
    },
  );

  test('a plural with a second placeholder fails, naming the key', () {
    _expectRejected(
      {
        'app_en.arb': '''{
  "@@locale": "en",
  "invites": "{count, plural, one{{name} sent {count} invite} other{{name} sent {count} invites}}",
  "@invites": {"x-native": ["app"], "placeholders": {"count": {"type": "int"}, "name": {"type": "String"}}}
}''',
      },
      ['invites'],
    );
  });

  test('a zero plural case fails, naming the key', () {
    _expectRejected(
      {
        'app_en.arb': '''{
  "@@locale": "en",
  "chats": "{count, plural, zero{No chats} other{{count} chats}}",
  "@chats": {"x-native": ["app"], "placeholders": {"count": {"type": "int"}}}
}''',
      },
      ['chats', 'zero'],
    );
  });

  test('a translation whose plural shape differs from the template fails', () {
    _expectRejected(
      {
        'app_en.arb': '''{
  "@@locale": "en",
  "chats": "{count} chats",
  "@chats": {"x-native": ["app"], "placeholders": {"count": {"type": "int"}}}
}''',
        'app_de.arb': '{"@@locale": "de", "chats": "{count, plural, one{{count} Chat} other{{count} Chats}}"}',
      },
      ['chats', 'de'],
    );
    _expectRejected(
      {
        'app_en.arb': '''{
  "@@locale": "en",
  "chats": "{count, plural, one{{count} chat} other{{count} chats}}",
  "@chats": {"x-native": ["app"], "placeholders": {"count": {"type": "int"}}}
}''',
        'app_de.arb': '{"@@locale": "de", "chats": "{count} Chats"}',
      },
      ['chats', 'de'],
    );
  });

  test('an orphaned language folder is stale', () {
    final repo = _repo({
      'app_en.arb': '{"@@locale": "en", "k": "K", "@k": {"x-native": ["app"]}}',
    });
    File('${repo.path}/android/app/src/main/res/values-fr/strings_l10n.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync('<resources/>');
    final outputs = buildOutputs(repo);
    writeOutputs(repo, outputs);
    expect(staleFiles(repo, outputs), [
      'android/app/src/main/res/values-fr/strings_l10n.xml',
    ]);
  });

  test('deleting orphans leaves hand-written resource files alone', () {
    final repo = _repo({
      'app_en.arb': '{"@@locale": "en", "k": "K", "@k": {"x-native": ["app"]}}',
    });
    const res = 'android/app/src/main/res';
    for (final path in [
      '$res/values-xx/strings_l10n.xml',
      '$res/values/strings.xml',
      '$res/values/colors.xml',
    ]) {
      File('${repo.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync('<resources/>');
    }
    final outputs = buildOutputs(repo);
    writeOutputs(repo, outputs);
    deleteOrphans(repo, outputs);
    expect(
      File('${repo.path}/$res/values-xx/strings_l10n.xml').existsSync(),
      isFalse,
    );
    expect(
      File('${repo.path}/$res/values/strings.xml').readAsStringSync(),
      '<resources/>',
    );
    expect(File('${repo.path}/$res/values/colors.xml').existsSync(), isTrue);
    expect(
      File('${repo.path}/$res/values/strings_l10n.xml').existsSync(),
      isTrue,
    );
  });

  test('a translation using an undeclared placeholder fails, naming key and locale', () {
    _expectRejected(
      {
        'app_en.arb':
            '{"@@locale": "en", "k": "K", "@k": {"x-native": ["app"]}}',
        'app_de.arb': '{"@@locale": "de", "k": "K {extra}"}',
      },
      ['k', 'de', 'extra'],
    );
  });

  test('native metadata without a message fails, naming the key', () {
    _expectRejected(
      {'app_en.arb': '{"@@locale": "en", "@ghost": {"x-native": ["app"]}}'},
      ['ghost'],
    );
  });

  test('a leading question mark and a backslash are escaped for Android', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb': r'''{
  "@@locale": "en",
  "q": "?Why",
  "@q": {"x-native": ["app"]},
  "b": "a\\b",
  "@b": {"x-native": ["app"]}
}''',
      }),
    );
    final android = out['android/app/src/main/res/values/strings_l10n.xml']!;
    expect(android, contains(r'<string name="q">\?Why</string>'));
    expect(android, contains(r'<string name="b">a\\b</string>'));
  });

  test('every language carries a marker naming its ARB locale, so the '
      'platform can say which one it picked', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb': '''{
  "@@locale": "en",
  "k": "K",
  "@k": {"x-native": ["zuno_notifications"]}
}''',
        'app_el.arb': '{"@@locale": "el", "k": "Κ"}',
      }),
    );
    const res = 'android/app/src/main/res';
    expect(
      out['$res/values/strings_l10n.xml'],
      contains('<string name="l10n_locale">en</string>'),
    );
    expect(
      out['$res/values-el/strings_l10n.xml'],
      contains('<string name="l10n_locale">el</string>'),
    );
    expect(_catalogLocalizations(out, 'l10n_locale'), {
      'el': {
        'stringUnit': {'state': 'translated', 'value': 'el'},
      },
      'en': {
        'stringUnit': {'state': 'translated', 'value': 'en'},
      },
    });
    expect(
      out['ios/Shared/L10n.swift'],
      contains(
        'static var appLocale: String { Bundle.main.localizedString(forKey: "l10n_locale", value: "en", table: nil) }',
      ),
    );
  });

  test('a base file declaring its region is tagged with it on both '
      'platforms, its Android folder stays the catch-all', () {
    final out = buildOutputs(
      _repo({
        'app_en.arb':
            '{"@@locale": "en", "k": "K", "@k": {"x-native": ["app", "ios"]}}',
        'app_pt.arb': '{"@@locale": "pt", "@@x-region": "BR", "k": "K"}',
        'app_pt_PT.arb': '{"@@locale": "pt_PT", "k": "K"}',
      }),
    );
    const res = 'android/app/src/main/res';
    expect(
      out['$res/values-pt/strings_l10n.xml'],
      contains('<string name="l10n_locale">pt</string>'),
    );
    expect(
      out['$res/values-pt-rPT/strings_l10n.xml'],
      contains('<string name="l10n_locale">pt_PT</string>'),
    );
    final config = out['$res/xml/locales_config.xml']!;
    expect(config, contains('<locale android:name="pt-BR"/>'));
    expect(config, contains('<locale android:name="pt-PT"/>'));
    expect(config, isNot(contains('<locale android:name="pt"/>')));
    expect(
      _catalogLocalizations(out, 'k').keys,
      unorderedEquals(['en', 'pt-BR', 'pt-PT']),
    );
    for (final plist in [
      'ios/Runner/Info.plist',
      'ios/NotificationService/Info.plist',
      'ios/ShareExtension/Info.plist',
    ]) {
      expect(out[plist], contains('<string>pt-BR</string>'));
      expect(out[plist], contains('<string>pt-PT</string>'));
      expect(out[plist], isNot(contains('<string>pt</string>')));
    }
  });

  group('regional files need their base to declare a region', () {
    test('a base without one fails, naming both files', () {
      _expectRejected(
        {
          'app_en.arb': '{"@@locale": "en", "k": "K"}',
          'app_pt.arb': '{"@@locale": "pt", "k": "K"}',
          'app_pt_PT.arb': '{"@@locale": "pt_PT", "k": "K"}',
        },
        ['pt_PT', 'app_pt.arb', '@@x-region'],
      );
    });

    test('a missing base fails, naming the regional file', () {
      _expectRejected(
        {
          'app_en.arb': '{"@@locale": "en", "k": "K"}',
          'app_pt_PT.arb': '{"@@locale": "pt_PT", "k": "K"}',
        },
        ['pt_PT', 'app_pt.arb'],
      );
    });

    test('a base declaring a region a regional file already has fails', () {
      _expectRejected(
        {
          'app_en.arb': '{"@@locale": "en", "k": "K"}',
          'app_pt.arb': '{"@@locale": "pt", "@@x-region": "PT", "k": "K"}',
          'app_pt_PT.arb': '{"@@locale": "pt_PT", "k": "K"}',
        },
        ['pt', 'PT'],
      );
    });

    test('a region on a language without regional files fails', () {
      _expectRejected(
        {
          'app_en.arb': '{"@@locale": "en", "k": "K"}',
          'app_el.arb': '{"@@locale": "el", "@@x-region": "GR", "k": "K"}',
        },
        ['el', '@@x-region'],
      );
    });

    test('a region on a regional file fails', () {
      _expectRejected(
        {
          'app_en.arb': '{"@@locale": "en", "k": "K"}',
          'app_pt.arb': '{"@@locale": "pt", "@@x-region": "BR", "k": "K"}',
          'app_pt_PT.arb':
              '{"@@locale": "pt_PT", "@@x-region": "AO", "k": "K"}',
        },
        ['pt_PT', '@@x-region'],
      );
    });

    test('a region that is not two capital letters or three digits fails', () {
      _expectRejected(
        {
          'app_en.arb': '{"@@locale": "en", "k": "K"}',
          'app_pt.arb': '{"@@locale": "pt", "@@x-region": "br", "k": "K"}',
          'app_pt_PT.arb': '{"@@locale": "pt_PT", "k": "K"}',
        },
        ['pt', 'br'],
      );
    });
  });

  test('an ARB key named like the locale marker fails', () {
    _expectRejected(
      {
        'app_en.arb': '''{
  "@@locale": "en",
  "l10n_locale": "Mine",
  "@l10n_locale": {"x-native": ["app"]}
}''',
      },
      ['l10n_locale'],
    );
  });
}
