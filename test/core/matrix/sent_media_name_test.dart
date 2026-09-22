import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/sent_media_name.dart';

void main() {
  test('photos are named by their output format only', () {
    expect(sentPhotoName('image/jpeg'), 'photo.jpg');
    expect(sentPhotoName('image/png'), 'photo.png');
  });

  test('videos get one generic name', () {
    expect(sentVideoName, 'video.mp4');
  });
}
