import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _namedFromDart = [
  (RegExp(r"RawResourceAndroidNotificationSound\('([^']+)'\)"), 'raw'),
  (RegExp(r"'@drawable/([^']+)'"), 'drawable'),
];

Set<(String, String)> _resourcesNamedFromDart() => {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      for (final (pattern, type) in _namedFromDart)
        for (final match in pattern.allMatches(file.readAsStringSync()))
          (type, match[1]!),
};

bool _hasResource(String type, String name) =>
    Directory('android/app/src/main/res').listSync().any(
      (folder) =>
          folder is Directory &&
          RegExp('^$type(-.+)?\$').hasMatch(folder.path.split('/').last) &&
          folder.listSync().any(
            (file) => file.uri.pathSegments.last.startsWith('$name.'),
          ),
    );

void main() {
  test('every resource Dart names survives release resource shrinking', () {
    final resources = _resourcesNamedFromDart();
    expect(
      resources.map((resource) => resource.$1),
      containsAll(['raw', 'drawable']),
    );

    final keep = File('android/app/src/main/res/raw/keep.xml');
    expect(keep.existsSync(), isTrue, reason: 'res/raw/keep.xml is missing');
    final kept = RegExp(r'tools:keep="([^"]*)"')
        .firstMatch(keep.readAsStringSync())?[1]
        ?.split(',')
        .map((entry) => entry.trim())
        .toSet();

    for (final (type, name) in resources) {
      expect(kept, contains('@$type/$name'));
      expect(
        _hasResource(type, name),
        isTrue,
        reason: 'res has no $type $name',
      );
    }
  });
}
