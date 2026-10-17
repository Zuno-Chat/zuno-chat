import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/forbidden_apis.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('forbidden_apis'));

  tearDown(() => root.deleteSync(recursive: true));

  List<int> binary(String text) => [0, 0xff, ...utf8.encode(text), 0, 0xff];

  List<int> utf16le(String text) => [
    0,
    0xff,
    for (final unit in text.codeUnits) ...[unit, 0],
  ];

  String write(String path, List<int> bytes) {
    final file = File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  String zip(String dir, String name, [String command = r'zip -q -r "$0" .']) {
    final out = '${root.path}/$name';
    File(out).parent.createSync(recursive: true);
    final result = Process.runSync('sh', [
      '-c',
      command,
      out,
    ], workingDirectory: '${root.path}/$dir');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return out;
  }

  test('passes a clean APK and counts every file it read', () {
    write('apk/classes.dex', binary('Landroid/app/Activity;'));
    write('apk/AndroidManifest.xml', utf16le('im.zuno.chat'));
    write('apk/lib/arm64-v8a/libapp.so', binary('zuno'));
    final apk = zip('apk', 'app-release.apk');

    final scan = scanArtifact(apk);

    expect(scan.findings, isEmpty);
    expect(scan.files, 3);
  });

  test('finds every marker written as UTF-8 or as UTF-16LE', () {
    final expected = <Finding>{};
    for (final (index, marker) in forbiddenMarkers.keys.indexed) {
      expected
        ..add((file: write('app/utf8_$index', binary(marker)), marker: marker))
        ..add((
          file: write('app/utf16_$index', utf16le(marker)),
          marker: marker,
        ));
    }

    final scan = scanArtifact('${root.path}/app');

    expect(scan.findings.toSet(), expected);
    expect(scan.files, expected.length);
  });

  test('names the dex entry in an AAB that references a framework API', () {
    write('aab/base/dex/classes.dex', binary('Landroid/app/Activity;'));
    write(
      'aab/base/dex/classes2.dex',
      binary('Landroid/app/contentsafety/ContentSafetyManager;'),
    );
    write('aab/base/manifest/AndroidManifest.xml', binary('im.zuno.chat'));
    final aab = zip('aab', 'app-release.aab');

    expect(scanArtifact(aab).findings, [
      (
        file: '$aab!/base/dex/classes2.dex',
        marker: 'android/app/contentsafety',
      ),
    ]);
  });

  test('looks inside an archive nested in the APK', () {
    write('inner/classes.dex', binary('com.google.android.safetycore'));
    zip('inner', 'apk/assets/plugin.zip');
    write('apk/classes.dex', binary('Landroid/app/Activity;'));
    final apk = zip('apk', 'app-release.apk');

    expect(scanArtifact(apk).findings, [
      (
        file: '$apk!/assets/plugin.zip!/classes.dex',
        marker: 'com.google.android.safetycore',
      ),
    ]);
  });

  test("finds a framework link and an entitlement in an IPA's extension and "
      'embedded framework', () {
    write('ipa/Payload/Runner.app/Runner', binary('/usr/lib/libSystem.dylib'));
    write(
      'ipa/Payload/Runner.app/PlugIns/Share.appex/Share',
      binary(
        '/System/Library/Frameworks/SensitiveContentAnalysis.framework/'
        'SensitiveContentAnalysis',
      ),
    );
    write(
      'ipa/Payload/Runner.app/Frameworks/Scan.framework/Scan',
      binary('<key>com.apple.developer.sensitivecontentanalysis.client</key>'),
    );
    final ipa = zip('ipa', 'Zuno.ipa');

    expect(scanArtifact(ipa).findings.toSet(), {
      (
        file: '$ipa!/Payload/Runner.app/PlugIns/Share.appex/Share',
        marker: 'SensitiveContentAnalysis',
      ),
      (
        file: '$ipa!/Payload/Runner.app/Frameworks/Scan.framework/Scan',
        marker: 'com.apple.developer.sensitivecontentanalysis.client',
      ),
    });
  });

  test('reads stored, zip64 and streamed archives', () {
    write('apk/classes.dex', binary('Landroid/app/contentsafety/X;'));

    for (final (name, command) in [
      ('stored.apk', r'zip -q -r -0 "$0" .'),
      ('zip64.apk', r'zip -q -r -fz "$0" .'),
      ('streamed.apk', r'zip -q -r - . | cat > "$0"'),
    ]) {
      final apk = zip('apk', name, command);

      expect(scanArtifact(apk).findings, [
        (file: '$apk!/classes.dex', marker: 'android/app/contentsafety'),
      ], reason: name);
    }
  });

  test('fails on an archive it cannot read', () {
    final apk = write('broken.apk', [0x50, 0x4b, 0x03, 0x04, 1, 2, 3]);

    expect(
      () => scanArtifact(apk),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(apk),
        ),
      ),
    );
  });

  test('fails when there is nothing to scan', () {
    Directory('${root.path}/Empty.app').createSync();

    for (final path in ['${root.path}/missing.ipa', '${root.path}/Empty.app']) {
      expect(
        () => scanArtifact(path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(path),
          ),
        ),
      );
    }
  });

  group('command line', () {
    final script = File('tool/ci/forbidden_apis.dart').absolute.path;

    ProcessResult run(List<String> args) =>
        Process.runSync('dart', [script, ...args]);

    test('exits non-zero naming the marker and the file', () {
      final clean = write('clean/Runner', binary('/usr/lib/libSystem.dylib'));
      final linked = write(
        'linked/Runner',
        binary('SensitiveContentAnalysis.framework'),
      );

      final result = run([clean, linked]);

      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('$linked contains "SensitiveContentAnalysis"'),
      );
      expect(result.stderr, isNot(contains(clean)));
    });

    test('exits zero on a clean artifact and says what it read', () {
      final clean = write('clean/Runner', binary('/usr/lib/libSystem.dylib'));

      final result = run([clean]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains(clean));
    });

    test('exits non-zero without an artifact', () {
      expect(run([]).exitCode, 1);
    });
  });
}
