import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/sent_media_name.dart';

void main() {
  test('photos are named by their output format only', () {
    expect(sentPhotoName('image/jpeg'), 'photo.jpg');
    expect(sentPhotoName('image/png'), 'photo.png');
  });

  test('a GIF or WebP sent untouched keeps its own extension', () {
    expect(sentPhotoName('image/gif'), 'photo.gif');
    expect(sentPhotoName('image/webp'), 'photo.webp');
  });

  test('videos get one generic name', () {
    expect(sentVideoName, 'video.mp4');
  });
}
