import 'dart:convert';
import 'dart:io';

import 'package:zuno_emoji/src/emoji_entry.dart';
import 'package:zuno_emoji/src/fold_core.dart';

import 'emoji_sources.dart';

const unicodeVersion = '18.0';
const cldrRelease = '49';

const languages = {
  'en': ['en'],
  'da': ['da'],
  'de': ['de'],
  'el': ['el'],
  'es': ['es'],
  'fr': ['fr'],
  'it': ['it'],
  'nb': ['no'],
  'nl': ['nl'],
  'pl': ['pl'],
  'pt': ['pt'],
  'pt_PT': ['pt', 'pt_PT'],
  'sq': ['sq'],
  'sv': ['sv'],
};

const _skinTones = ['🏻', '🏼', '🏽', '🏾', '🏿'];
const _foldLimit = 0x2000;

final _root = File.fromUri(Platform.script).parent.parent;

Future<void> main() async {
  final client = HttpClient();
  try {
    final emoji = parseEmojiTest(
      await _get(
        client,
        'https://unicode.org/Public/$unicodeVersion.0/emoji/emoji-test.txt',
      ),
    );
    final fold = {
      for (final MapEntry(:key, :value) in foldMap(
        await _get(
          client,
          'https://unicode.org/Public/$unicodeVersion.0/ucd/UnicodeData.txt',
        ),
      ).entries)
        if (key.runes.first < _foldLimit) key: value,
    };
    _write('lib/src/data/emoji_table.g.dart', _table(emoji));
    _write('lib/src/data/fold.g.dart', _fold(fold));
    final flags = [
      for (final e in emoji)
        if (e.category == EmojiCategory.flags) e.emoji,
    ];
    for (final MapEntry(key: language, value: locales) in languages.entries) {
      var annotations = <String, Annotation>{};
      final regionNames = <String, String>{};
      for (final locale in locales) {
        annotations = mergeAnnotations(
          mergeAnnotations(
            parseAnnotations(await _cldr(client, 'annotations', locale)),
            parseAnnotations(await _cldr(client, 'annotationsDerived', locale)),
          ),
          annotations,
        );
        regionNames
          ..addAll(parseRegionNames(await _cldr(client, 'main', locale)))
          ..addAll(
            parseRegionNames(await _cldr(client, 'subdivisions', locale)),
          );
      }
      annotations = fillFlagNames(annotations, flags, regionNames);
      _write('assets/names/$language.json', _names(emoji, annotations, fold));
    }
  } finally {
    client.close();
  }
  final format = await Process.run('dart', [
    'format',
    'lib/src/data',
  ], workingDirectory: _root.path);
  stdout.write(format.stdout);
}

Future<String> _cldr(HttpClient client, String folder, String locale) => _get(
  client,
  'https://raw.githubusercontent.com/unicode-org/cldr/release-$cldrRelease/common/$folder/$locale.xml',
);

Future<String> _get(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} for $url');
  }
  return response.transform(utf8.decoder).join();
}

String _table(List<EmojiEntry> emoji) {
  final out = StringBuffer()
    ..writeln("import '../emoji_entry.dart';")
    ..writeln()
    ..writeln(
      "const emojiDataVersion = 'unicode-$unicodeVersion+cldr-$cldrRelease';",
    )
    ..writeln()
    ..writeln(
      'const emojiLanguages = {${languages.keys.map(_literal).join(', ')}};',
    )
    ..writeln()
    ..writeln('const emojiTable = <EmojiEntry>[');
  for (final e in emoji) {
    out.write(
      '  EmojiEntry(${_literal(e.emoji)}, EmojiCategory.${e.category.name}, ${e.version}',
    );
    if (e.tones != ToneKind.none) {
      out.write(
        ', ToneKind.${e.tones.name}, [${e.variants.map(_literal).join(', ')}]',
      );
    }
    out.writeln('),');
  }
  out.writeln('];');
  return out.toString();
}

String _fold(Map<String, String> fold) => [
  'const foldMap = <String, String>{',
  for (final e in fold.entries) '  ${_literal(e.key)}: ${_literal(e.value)},',
  '};',
  '',
].join('\n');

String _names(
  List<EmojiEntry> emoji,
  Map<String, Annotation> annotations,
  Map<String, String> fold,
) {
  List<Object?> entry(String emoji) {
    final annotation = annotations[lookupKey(emoji)];
    final keywords = {
      for (final k in annotation?.keywords ?? const <String>[])
        foldWith(fold, k),
    };
    return [annotation?.name, keywords.join('|')];
  }

  return jsonEncode({
    'tones': [for (final t in _skinTones) annotations[t]?.name],
    'names': [for (final e in emoji) entry(e.emoji)],
  });
}

String _literal(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

void _write(String path, String content) {
  final file = File('${_root.path}/$path')..createSync(recursive: true);
  file.writeAsStringSync(content);
  stdout.writeln('$path: ${file.lengthSync()} bytes');
}
