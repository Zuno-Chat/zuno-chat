import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _sqlite3Import = RegExp('[\'"]package:sqlite3/');

Map<String, Directory> _packageLibs() {
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final packages = (config['packages']! as List).cast<Map<String, Object?>>();
  return {
    for (final package in packages)
      package['name']! as String: Directory.fromUri(
        configFile.absolute.uri
            .resolve(_asDirectory(package['rootUri']! as String))
            .resolve(package['packageUri'] as String? ?? 'lib/'),
      ),
  };
}

String _asDirectory(String uri) => uri.endsWith('/') ? uri : '$uri/';

bool _importsSqlite3(Directory lib) =>
    lib.existsSync() &&
    lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .any((file) => _sqlite3Import.hasMatch(file.readAsStringSync()));

bool _mayUseSqlite3(Directory lib) {
  final pubspec = File.fromUri(lib.parent.uri.resolve('pubspec.yaml'));
  return pubspec.existsSync() && pubspec.readAsStringSync().contains('sqlite3');
}

void main() {
  test('the build does not bundle SQLite for package:sqlite3', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('sqlite3:\n      source: system'),
    );
  });

  test('no package imports package:sqlite3, so Android never needs it', () {
    final libs = _packageLibs();
    expect(
      _importsSqlite3(libs['sqlite3']!),
      isTrue,
      reason: 'the import check must see the imports sqlite3 itself has',
    );

    final importers = [
      for (final MapEntry(key: name, value: lib) in libs.entries)
        if (name != 'sqlite3' && _mayUseSqlite3(lib) && _importsSqlite3(lib))
          name,
    ];

    expect(
      importers,
      isEmpty,
      reason:
          'pubspec.yaml sets sqlite3 to the system library, so the build '
          'bundles no SQLite, and Android has no system copy an app can '
          'load. Remove that user define before anything uses sqlite3.',
    );
  });
}
