import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/l10n/native_strings.dart';

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
      final ios = out['ios/Shared/Localizable.xcstrings']!;
      expect(RegExp('"de"').allMatches(ios).length, 1);
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
}
