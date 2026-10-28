import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _soundsPlayedByName() => {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      for (final match in RegExp(
        r"RawResourceAndroidNotificationSound\('([^']+)'\)",
      ).allMatches(file.readAsStringSync()))
        match[1]!,
};

void main() {
  test(
    'every sound Dart plays by name survives release resource shrinking',
    () {
      final sounds = _soundsPlayedByName();
      expect(sounds, isNotEmpty);

      final keep = File('android/app/src/main/res/raw/keep.xml');
      expect(keep.existsSync(), isTrue, reason: 'res/raw/keep.xml is missing');
      final kept = RegExp(r'tools:keep="([^"]*)"')
          .firstMatch(keep.readAsStringSync())?[1]
          ?.split(',')
          .map((entry) => entry.trim())
          .toSet();

      for (final sound in sounds) {
        expect(kept, contains('@raw/$sound'));
        expect(
          Directory('android/app/src/main/res/raw')
              .listSync()
              .any((file) => file.uri.pathSegments.last.startsWith('$sound.')),
          isTrue,
          reason: 'res/raw has no $sound file',
        );
      }
    },
  );
}
