import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/looks_like_video.dart';

void main() {
  test('mimeType wins when set, regardless of extension', () {
    expect(
      looksLikeVideo(XFile('/tmp/clip.mp4', mimeType: 'video/mp4')),
      isTrue,
    );
    expect(
      looksLikeVideo(XFile('/tmp/photo.jpg', mimeType: 'image/jpeg')),
      isFalse,
    );
    expect(
      looksLikeVideo(XFile('/tmp/weird.jpg', mimeType: 'video/mp4')),
      isTrue,
    );
  });

  for (final ext in [
    '.mp4',
    '.MOV',
    '.m4v',
    '.3gp',
    '.mkv',
    '.webm',
    '.avi',
    '.wmv',
  ]) {
    test('$ext is recognized as video by extension when mimeType is unset', () {
      expect(looksLikeVideo(XFile('/tmp/clip$ext')), isTrue);
    });
  }

  for (final ext in ['.jpg', '.jpeg', '.png', '.gif', '.heic', '.webp']) {
    test(
      '$ext is not treated as video by extension when mimeType is unset',
      () {
        expect(looksLikeVideo(XFile('/tmp/photo$ext')), isFalse);
      },
    );
  }

  test('a path with no extension at all is not treated as video', () {
    expect(looksLikeVideo(XFile('/tmp/blob')), isFalse);
  });
}
