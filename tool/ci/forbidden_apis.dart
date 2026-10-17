import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const forbiddenMarkers = {
  'com.google.android.safetycore': 'Google SafetyCore',
  'com/google/android/safetycore': 'Google SafetyCore',
  'android.app.contentsafety': "Android's ContentSafetyManager",
  'android/app/contentsafety': "Android's ContentSafetyManager",
  'SensitiveContentAnalysis': "Apple's SensitiveContentAnalysis framework",
  'com.apple.developer.sensitivecontentanalysis.client':
      "Apple's SensitiveContentAnalysis entitlement",
};

typedef Finding = ({String file, String marker});

typedef Scan = ({int files, List<Finding> findings});

void main(List<String> args) {
  if (args.isEmpty) {
    _fail('usage: dart tool/ci/forbidden_apis.dart <apk|aab|ipa|app>...');
    return;
  }
  try {
    final findings = <Finding>[];
    for (final path in args) {
      final scan = scanArtifact(path);
      findings.addAll(scan.findings);
      stdout.writeln('forbidden_apis: read ${scan.files} files in $path');
    }
    if (findings.isEmpty) return;
    for (final (:file, :marker) in findings) {
      _fail('$file contains "$marker" (${forbiddenMarkers[marker]})');
    }
    _fail(
      'Zuno must never ship an on-device content-scanning API; '
      'drop the dependency or code that brings it in.',
    );
  } on FormatException catch (error) {
    _fail(error.message);
  } on FileSystemException catch (error) {
    _fail('${error.path}: ${error.message}');
  }
}

void _fail(String message) {
  stderr.writeln('forbidden_apis: $message');
  exitCode = 1;
}

Scan scanArtifact(String path) {
  final files = switch (FileSystemEntity.typeSync(path)) {
    FileSystemEntityType.directory => Directory(
      path,
    ).listSync(recursive: true, followLinks: false).whereType<File>(),
    FileSystemEntityType.file => [File(path)],
    _ => throw FormatException('$path: not found'),
  };
  final leaves = [
    for (final file in files) ..._leaves(file.path, file.readAsBytesSync()),
  ];
  if (leaves.isEmpty) throw FormatException('$path: no files to scan');
  return (
    files: leaves.length,
    findings: [
      for (final (:file, :markers) in leaves)
        for (final marker in markers) (file: file, marker: marker),
    ],
  );
}

Iterable<({String file, Set<String> markers})> _leaves(
  String file,
  Uint8List bytes,
) sync* {
  if (!_isZip(bytes)) {
    yield (file: file, markers: _markersIn(bytes));
    return;
  }
  for (final (name, content) in _zipEntries(file, bytes)) {
    yield* _leaves('$file!/$name', content);
  }
}

final _markerPattern = RegExp(
  [
    for (final marker in forbiddenMarkers.keys) ...[
      marker,
      String.fromCharCodes([
        for (final unit in marker.codeUnits) ...[unit, 0],
      ]),
    ],
  ].map(RegExp.escape).join('|'),
);

Set<String> _markersIn(Uint8List bytes) => {
  for (final match in _markerPattern.allMatches(latin1.decode(bytes)))
    match[0]!.replaceAll('\x00', ''),
};

const _localHeader = 0x04034b50;
const _centralHeader = 0x02014b50;
const _endRecord = 0x06054b50;
const _zip64EndLocator = 0x07064b50;
const _zip64EndRecord = 0x06064b50;
const _stored = 0;
const _deflated = 8;

bool _isZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    ByteData.sublistView(bytes).getUint32(0, Endian.little) == _localHeader;

Iterable<(String, Uint8List)> _zipEntries(String file, Uint8List zip) sync* {
  final data = ByteData.sublistView(zip);
  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);
  int u64(int at) => data.getUint64(at, Endian.little);
  Never broken(String why) => throw FormatException('$file: $why');
  Uint8List inflate(String name, Uint8List raw) {
    try {
      return ZLibDecoder(raw: true).convert(raw) as Uint8List;
    } on FormatException {
      broken('$name is not valid deflate data');
    }
  }

  try {
    final earliestEnd = max(0, zip.length - 22 - 0xffff);
    var end = zip.length - 22;
    while (end >= earliestEnd && u32(end) != _endRecord) {
      end--;
    }
    if (end < earliestEnd) broken('not a readable zip archive');
    var count = u16(end + 10);
    var entry = u32(end + 16);
    if (end >= 20 && u32(end - 20) == _zip64EndLocator) {
      final record = u64(end - 12);
      if (u32(record) != _zip64EndRecord) broken('broken zip64 end record');
      count = u64(record + 32);
      entry = u64(record + 48);
    }

    for (var i = 0; i < count; i++) {
      if (u32(entry) != _centralHeader) broken('broken central directory');
      final flags = u16(entry + 8);
      final method = u16(entry + 10);
      final compressedSize = u32(entry + 20);
      final nameLength = u16(entry + 28);
      final local = u32(entry + 42);
      final name = utf8.decode(
        Uint8List.sublistView(zip, entry + 46, entry + 46 + nameLength),
        allowMalformed: true,
      );
      entry += 46 + nameLength + u16(entry + 30) + u16(entry + 32);

      if (name.endsWith('/')) continue;
      if (flags & 1 != 0) broken('$name is encrypted');
      if (u32(local) != _localHeader) broken('broken local header of $name');
      final start = local + 30 + u16(local + 26) + u16(local + 28);
      final raw = Uint8List.sublistView(zip, start, start + compressedSize);
      yield (
        name,
        switch (method) {
          _stored => raw,
          _deflated => inflate(name, raw),
          _ => broken('$name uses unsupported compression method $method'),
        },
      );
    }
  } on RangeError {
    broken('truncated or unsupported zip archive');
  }
}
