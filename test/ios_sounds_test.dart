import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

({String format, int channels, int bits}) _formatOf(File sound) {
  final bytes = ByteData.sublistView(sound.readAsBytesSync());
  String id(int at) =>
      String.fromCharCodes(Uint8List.sublistView(bytes, at, at + 4));

  expect(id(0), 'caff', reason: '${sound.path} is not a CAF file');
  for (var at = 8; at + 12 <= bytes.lengthInBytes;) {
    final body = at + 12;
    if (id(at) == 'desc') {
      return (
        format: id(body + 8),
        channels: bytes.getUint32(body + 24),
        bits: bytes.getUint32(body + 28),
      );
    }
    at = body + bytes.getInt64(at + 4);
  }
  throw StateError('${sound.path} has no format');
}

void main() {
  test('every iOS sound is 16-bit PCM, so its pure tone plays without '
      'codec hiss', () {
    final sounds = [
      for (final file in Directory('ios/Runner').listSync())
        if (file is File && file.path.endsWith('.caf')) file,
    ];
    expect(sounds, isNotEmpty);

    for (final sound in sounds) {
      expect(_formatOf(sound), (
        format: 'lpcm',
        channels: 1,
        bits: 16,
      ), reason: sound.path);
    }
  });
}
