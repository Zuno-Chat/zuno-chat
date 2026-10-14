import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _files(List<String> dirs, String extension) => [
  for (final dir in dirs)
    if (Directory(dir).existsSync())
      ...Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(extension)),
];

void main() {
  final template = jsonDecode(
    File('lib/l10n/app_en.arb').readAsStringSync(),
  ) as Map<String, Object?>;
  final keys = template.keys.where((k) => !k.startsWith('@')).toList();

  test('every ARB key is used', () {
    final dart = _files(['lib'], '.dart')
        .where((f) => !f.path.startsWith('lib/l10n/'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    final kotlin = _files([
      'android/app/src/main/kotlin',
      'packages/zuno_notifications/android/src/main/kotlin',
      'packages/zuno_call_style/android/src/main/kotlin',
    ], '.kt').map((f) => f.readAsStringSync()).join('\n');
    final swift =
        _files([
              'ios/Runner',
              'ios/NotifyShared',
              'ios/ShareExtension',
              'ios/NotificationService',
              'ios/Shared',
            ], '.swift')
            .where((f) => !f.path.endsWith('L10n.swift'))
            .map((f) => f.readAsStringSync())
            .join('\n');
    final unused = [
      for (final key in keys)
        if (!RegExp('\\.$key\\b').hasMatch(dart) &&
            !RegExp('R\\.(string|plurals)\\.$key\\b').hasMatch(kotlin) &&
            !RegExp('L10n\\.$key\\b').hasMatch(swift) &&
            (template['@$key'] as Map?)?['x-ios-infoplist'] == null)
          key,
    ];
    expect(unused, isEmpty);
  });

  test('translations only contain template keys', () {
    for (final file in _files(['lib/l10n'], '.arb')) {
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final extra = arb.keys.where(
        (k) => !k.startsWith('@') && !template.containsKey(k),
      );
      expect(extra, isEmpty, reason: file.path);
    }
  });
}
