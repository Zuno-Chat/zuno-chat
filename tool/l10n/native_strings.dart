import 'dart:convert';
import 'dart:io';

const templateLocale = 'en';

const androidResDirs = {
  'app': 'android/app/src/main/res',
  'zuno_notifications': 'packages/zuno_notifications/android/src/main/res',
  'zuno_call_style': 'packages/zuno_call_style/android/src/main/res',
};

const _localesConfig = 'android/app/src/main/res/xml/locales_config.xml';
const _catalog = 'ios/Shared/Localizable.xcstrings';
const _swift = 'ios/Shared/L10n.swift';
const _plistCatalog = 'ios/Runner/InfoPlist.xcstrings';
const _runnerPlist = 'ios/Runner/Info.plist';
const _extensionPlists = [
  'ios/NotificationService/Info.plist',
  'ios/ShareExtension/Info.plist',
];

final class Arb {
  Arb(this.locale, this.messages, this.metadata);

  factory Arb.parse(String fileName, String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    final locale =
        json['@@locale'] as String? ??
        RegExp(r'^app_(.+)\.arb$').firstMatch(fileName)!.group(1)!;
    final messages = <String, String>{};
    final metadata = <String, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key.startsWith('@@')) continue;
      if (key.startsWith('@')) {
        metadata[key.substring(1)] = value! as Map<String, Object?>;
      } else {
        messages[key] = value! as String;
      }
    }
    return Arb(locale, messages, metadata);
  }

  final String locale;
  final Map<String, String> messages;
  final Map<String, Map<String, Object?>> metadata;
}

sealed class Part {
  const Part();
}

final class Literal extends Part {
  const Literal(this.text);
  final String text;
}

final class Slot extends Part {
  const Slot(this.name);
  final String name;
}

final class Message {
  Message.simple(this.parts) : cases = const {}, selector = null;
  Message.plural(String this.selector, this.cases) : parts = const [];

  final List<Part> parts;
  final Map<String, List<Part>> cases;
  final String? selector;

  bool get isPlural => selector != null;

  bool get isFormatted => isPlural || parts.any((p) => p is Slot);

  Iterable<Slot> get slots =>
      [...parts, for (final value in cases.values) ...value].whereType<Slot>();
}

final _plural = RegExp(r'^\{(\w+),\s*plural,(.*)\}$', dotAll: true);
final _pluralCase = RegExp(r'\s*(one|two|few|many|other)\s*\{');
final _slot = RegExp(r'\{(\w+)\}');

Message parseMessage(String key, String source) {
  final plural = _plural.firstMatch(source);
  if (plural == null) return Message.simple(_parts(key, source));
  final body = plural.group(2)!;
  final cases = <String, List<Part>>{};
  var index = 0;
  while (body.substring(index).trim().isNotEmpty) {
    final match =
        _pluralCase.matchAsPrefix(body, index) ??
        (throw FormatException(
          '$key: unsupported plural case; zero and =n cases behave differently on Android and iOS, use one/two/few/many/other',
        ));
    final close = _closingBrace(key, body, match.end);
    cases[match.group(1)!] = _parts(key, body.substring(match.end, close));
    index = close + 1;
  }
  if (!cases.containsKey('other')) {
    throw FormatException('$key: a plural needs an other case');
  }
  return Message.plural(plural.group(1)!, cases);
}

int _closingBrace(String key, String text, int start) {
  var depth = 1;
  for (var i = start; i < text.length; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}' && --depth == 0) return i;
  }
  throw FormatException('$key: unbalanced braces');
}

List<Part> _parts(String key, String text) {
  final parts = <Part>[];
  var index = 0;
  for (final match in _slot.allMatches(text)) {
    if (match.start > index) {
      parts.add(Literal(text.substring(index, match.start)));
    }
    parts.add(Slot(match.group(1)!));
    index = match.end;
  }
  if (index < text.length) parts.add(Literal(text.substring(index)));
  if (parts.whereType<Literal>().any((p) => p.text.contains(RegExp('[{}]')))) {
    throw FormatException(
      '$key: native strings support plain text, {name} placeholders and one whole-message plural',
    );
  }
  return parts;
}

final class NativeString {
  NativeString(this.key, this.modules, this.plistKeys, this.order, this.ints);

  final String key;
  final List<String> modules;
  final List<String> plistKeys;
  final List<String> order;
  final Set<String> ints;

  bool get ios => modules.contains('ios');

  int position(String name) => order.indexOf(name) + 1;
}

List<NativeString> _nativeStrings(Arb template) => [
  for (final MapEntry(:key, :value) in template.metadata.entries)
    if (value['x-native'] != null || value['x-ios-infoplist'] != null)
      _nativeString(template, key, value),
];

NativeString _nativeString(
  Arb template,
  String key,
  Map<String, Object?> meta,
) {
  final modules = [...?(meta['x-native'] as List?)?.cast<String>()];
  for (final module in modules) {
    if (module != 'ios' && !androidResDirs.containsKey(module)) {
      throw FormatException('$key: unknown x-native target $module');
    }
  }
  final declared = (meta['placeholders'] as Map<String, Object?>?) ?? {};
  final source = template.messages[key];
  if (source == null) {
    throw FormatException('$key: native metadata without a message');
  }
  final message = parseMessage(key, source);
  final order = {
    ...declared.keys,
    for (final slot in message.slots)
      if (!declared.containsKey(slot.name)) slot.name,
  }.toList();
  final ints = {
    for (final MapEntry(:key, :value) in declared.entries)
      if (const {'int', 'num'}.contains((value! as Map)['type'])) key,
  };
  final plistKeys = [...?(meta['x-ios-infoplist'] as List?)?.cast<String>()];
  if (plistKeys.isNotEmpty && order.isNotEmpty) {
    throw FormatException('$key: Info.plist text cannot have placeholders');
  }
  final selector = message.selector;
  if (selector != null) {
    final type = (declared[selector] as Map?)?['type'];
    if (type != 'int') {
      throw FormatException(
        '$key: the plural selector $selector must be a declared int placeholder',
      );
    }
    if (order.length > 1) {
      throw FormatException(
        '$key: a native plural takes only its count placeholder, not ${order.where((n) => n != selector).join(', ')}',
      );
    }
  }
  return NativeString(key, modules, plistKeys, order, ints);
}

void _checkTranslations(List<NativeString> natives, List<Arb> arbs) {
  final template = arbs.first;
  for (final string in natives) {
    final selector = parseMessage(
      string.key,
      template.messages[string.key]!,
    ).selector;
    for (final arb in arbs.skip(1)) {
      final source = arb.messages[string.key];
      if (source == null) continue;
      final message = parseMessage(string.key, source);
      if (message.selector != selector) {
        throw FormatException(
          '${string.key}: the ${arb.locale} translation must ${selector == null ? 'be plain text like the template' : 'be a plural on $selector like the template'}',
        );
      }
      for (final slot in message.slots) {
        if (!string.order.contains(slot.name)) {
          throw FormatException(
            '${string.key}: ${arb.locale} uses placeholder ${slot.name} that the template does not declare',
          );
        }
      }
    }
  }
}

List<Arb> readArbs(Directory root) {
  final arbs = Directory('${root.path}/lib/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'app_.+\.arb$').hasMatch(f.path))
      .map((f) => Arb.parse(f.uri.pathSegments.last, f.readAsStringSync()))
      .toList();
  arbs.sort((a, b) {
    if (a.locale == templateLocale) return -1;
    if (b.locale == templateLocale) return 1;
    return a.locale.compareTo(b.locale);
  });
  return arbs;
}

String languageTag(String locale) => locale.replaceAll('_', '-');

String androidValuesDir(String locale) {
  if (locale == templateLocale) return 'values';
  final parts = locale.split(RegExp('[_-]'));
  return switch (parts) {
    [final language] => 'values-$language',
    [final language, final region] when region.length == 2 =>
      'values-$language-r$region',
    _ => 'values-b+${parts.join('+')}',
  };
}

Map<String, String> buildOutputs(Directory root) {
  final arbs = readArbs(root);
  final template = arbs.first;
  final natives = _nativeStrings(template);
  _checkTranslations(natives, arbs);
  final outputs = <String, String>{};
  for (final MapEntry(key: module, value: resDir) in androidResDirs.entries) {
    final strings = natives.where((n) => n.modules.contains(module)).toList();
    if (strings.isEmpty) continue;
    for (final arb in arbs) {
      final present = strings
          .where((n) => arb.messages.containsKey(n.key))
          .toList();
      if (present.isEmpty) continue;
      outputs['$resDir/${androidValuesDir(arb.locale)}/strings_l10n.xml'] =
          _androidStrings(present, arb);
    }
  }
  outputs[_localesConfig] = _localesConfigXml(arbs);
  final ios = natives.where((n) => n.ios).toList();
  final plist = natives.where((n) => n.plistKeys.isNotEmpty).toList();
  outputs[_catalog] = _xcstrings(ios, arbs, (n) => [n.key]);
  outputs[_plistCatalog] = _xcstrings(plist, arbs, (n) => n.plistKeys);
  outputs[_swift] = _swiftAccessors(ios);
  final languages = [for (final arb in arbs) languageTag(arb.locale)];
  var runner = File('${root.path}/$_runnerPlist').readAsStringSync();
  for (final string in plist) {
    for (final plistKey in string.plistKeys) {
      runner = _withPlistString(
        runner,
        plistKey,
        template.messages[string.key]!,
      );
    }
  }
  outputs[_runnerPlist] = _withLocalizations(runner, languages);
  for (final path in _extensionPlists) {
    outputs[path] = _withLocalizations(
      File('${root.path}/$path').readAsStringSync(),
      languages,
    );
  }
  return outputs;
}

List<String> staleFiles(Directory root, Map<String, String> outputs) => [
  for (final MapEntry(:key, :value) in outputs.entries)
    if (!File('${root.path}/$key').existsSync() ||
        File('${root.path}/$key').readAsStringSync() != value)
      key,
  ..._orphans(root, outputs),
];

void writeOutputs(Directory root, Map<String, String> outputs) {
  for (final MapEntry(:key, :value) in outputs.entries) {
    File('${root.path}/$key')
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
}

void deleteOrphans(Directory root, Map<String, String> outputs) {
  for (final path in _orphans(root, outputs)) {
    File('${root.path}/$path').deleteSync();
  }
}

List<String> _orphans(Directory root, Map<String, String> outputs) {
  final orphans = <String>[];
  for (final resDir in androidResDirs.values) {
    final dir = Directory('${root.path}/$resDir');
    if (!dir.existsSync()) continue;
    for (final values in dir.listSync().whereType<Directory>()) {
      final name = values.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final path = '$resDir/$name/strings_l10n.xml';
      if (name.startsWith('values') &&
          File('${root.path}/$path').existsSync() &&
          !outputs.containsKey(path)) {
        orphans.add(path);
      }
    }
  }
  return orphans;
}

String _androidStrings(List<NativeString> strings, Arb arb) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n',
  );
  for (final string in strings) {
    final message = parseMessage(string.key, arb.messages[string.key]!);
    if (message.isPlural) {
      buffer.writeln('    <plurals name="${string.key}">');
      for (final MapEntry(:key, :value) in message.cases.entries) {
        buffer.writeln(
          '        <item quantity="$key">${_androidValue(value, string, formatted: message.isFormatted)}</item>',
        );
      }
      buffer.writeln('    </plurals>');
    } else {
      buffer.writeln(
        '    <string name="${string.key}">${_androidValue(message.parts, string, formatted: message.isFormatted)}</string>',
      );
    }
  }
  buffer.write('</resources>\n');
  return buffer.toString();
}

String _androidValue(
  List<Part> parts,
  NativeString string, {
  required bool formatted,
}) {
  final value = parts
      .map(
        (part) => switch (part) {
          Literal(:final text) => _escapeAndroid(text, formatted: formatted),
          Slot(:final name) =>
            '%${string.position(name)}\$${string.ints.contains(name) ? 'd' : 's'}',
        },
      )
      .join();
  return value.startsWith('@') || value.startsWith('?') ? '\\$value' : value;
}

String _escapeAndroid(String text, {required bool formatted}) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", r"\'")
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return formatted ? escaped.replaceAll('%', '%%') : escaped;
}

String _localesConfigXml(List<Arb> arbs) => [
  '<?xml version="1.0" encoding="utf-8"?>',
  '<locale-config xmlns:android="http://schemas.android.com/apk/res/android">',
  for (final arb in arbs)
    '    <locale android:name="${languageTag(arb.locale)}"/>',
  '</locale-config>',
  '',
].join('\n');

String _iosValue(
  List<Part> parts,
  NativeString string, {
  required bool formatted,
}) => parts
    .map(
      (part) => switch (part) {
        Literal(:final text) => formatted ? text.replaceAll('%', '%%') : text,
        Slot(:final name) =>
          '%${string.position(name)}\$${string.ints.contains(name) ? 'lld' : '@'}',
      },
    )
    .join();

Map<String, Object?> _unit(String value) => {
  'stringUnit': {'state': 'translated', 'value': value},
};

String _xcstrings(
  List<NativeString> strings,
  List<Arb> arbs,
  List<String> Function(NativeString) catalogKeys,
) {
  final entries = <String, Object?>{};
  for (final string in strings) {
    final localizations = <String, Object?>{};
    for (final arb in arbs) {
      final source = arb.messages[string.key];
      if (source == null) continue;
      final message = parseMessage(string.key, source);
      localizations[languageTag(arb.locale)] = message.isPlural
          ? {
              'variations': {
                'plural': {
                  for (final MapEntry(:key, :value) in message.cases.entries)
                    key: _unit(
                      _iosValue(value, string, formatted: message.isFormatted),
                    ),
                },
              },
            }
          : _unit(
              _iosValue(message.parts, string, formatted: message.isFormatted),
            );
    }
    for (final key in catalogKeys(string)) {
      entries[key] = {
        'extractionState': 'manual',
        'localizations': localizations,
      };
    }
  }
  return '${_xcodeJson({'sourceLanguage': templateLocale, 'strings': entries, 'version': '1.0'})}\n';
}

String _xcodeJson(Object? value, [String indent = '']) {
  if (value is! Map<String, Object?>) return jsonEncode(value);
  if (value.isEmpty) return '{\n\n$indent}';
  final inner = '$indent  ';
  final keys = value.keys.toList()..sort();
  return '{\n${keys.map((k) => '$inner${jsonEncode(k)} : ${_xcodeJson(value[k], inner)}').join(',\n')}\n$indent}';
}

String _swiftAccessors(List<NativeString> strings) {
  final buffer = StringBuffer('import Foundation\n\nenum L10n {\n');
  for (final string in strings) {
    if (string.order.isEmpty) {
      buffer.writeln(
        '  static var ${string.key}: String { text("${string.key}") }',
      );
      continue;
    }
    final params = string.order
        .map((n) => '_ $n: ${string.ints.contains(n) ? 'Int' : 'String'}')
        .join(', ');
    buffer.writeln(
      '  static func ${string.key}($params) -> String {\n'
      '    String.localizedStringWithFormat(L10n.text("${string.key}"), ${string.order.join(', ')})\n'
      '  }',
    );
  }
  buffer.write(
    '\n  private static let missing = "\\u{1}"\n'
    '  private static let english = Bundle.main.path(forResource: "$templateLocale", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main\n'
    '\n  private static func text(_ key: String) -> String {\n'
    '    let localized = Bundle.main.localizedString(forKey: key, value: missing, table: nil)\n'
    '    return localized == missing ? english.localizedString(forKey: key, value: nil, table: nil) : localized\n'
    '  }\n}\n',
  );
  return buffer.toString();
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _withPlistString(String plist, String key, String value) {
  final pattern = RegExp(
    '(<key>${RegExp.escape(key)}</key>\\s*<string>)[^<]*(</string>)',
  );
  if (!pattern.hasMatch(plist)) throw FormatException('Info.plist has no $key');
  return plist.replaceFirstMapped(
    pattern,
    (m) => '${m[1]}${_xml(value)}${m[2]}',
  );
}

String _withLocalizations(String plist, List<String> languages) {
  final array =
      '<array>\n${languages.map((l) => '\t\t<string>$l</string>\n').join()}\t</array>';
  final existing = RegExp(
    r'<key>CFBundleLocalizations</key>\s*<array>[\s\S]*?</array>',
  );
  if (existing.hasMatch(plist)) {
    return plist.replaceFirst(
      existing,
      '<key>CFBundleLocalizations</key>\n\t$array',
    );
  }
  return plist.replaceFirst(
    '<dict>\n',
    '<dict>\n\t<key>CFBundleLocalizations</key>\n\t$array\n',
  );
}
