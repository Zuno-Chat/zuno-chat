import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef LibraryVersions = ({String matrix, String vodozemac});

const _lockAsset = 'pubspec.lock';

LibraryVersions parseLibraryVersions(String lock) {
  final lines = const LineSplitter().convert(lock);
  String version(String package) {
    final start = lines.indexOf('  $package:');
    if (start < 0) throw FormatException('$package is not in $_lockAsset');
    final line = lines
        .skip(start + 1)
        .takeWhile((line) => line.startsWith('    '))
        .firstWhere(
          (line) => line.startsWith('    version: '),
          orElse: () =>
              throw FormatException('$package has no version in $_lockAsset'),
        );
    return line.split('"')[1];
  }

  return (matrix: version('matrix'), vodozemac: version('vodozemac'));
}

final libraryVersionsProvider = FutureProvider<LibraryVersions>((ref) async {
  final lock = await rootBundle.load(_lockAsset);
  return parseLibraryVersions(
    utf8.decode(
      lock.buffer.asUint8List(lock.offsetInBytes, lock.lengthInBytes),
    ),
  );
}, retry: (_, _) => null);
