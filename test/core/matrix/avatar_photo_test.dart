import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/avatar_photo.dart';

void main() {
  test('an avatar loses the GPS location of the photo it came from and stays '
      'upright', () async {
    final photo = img.Image(width: 800, height: 400)
      ..exif.imageIfd.orientation = 6;
    photo.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
    photo.exif.gpsIfd[0x0002] = img.IfdValueRational(52, 1);

    final avatar = await prepareAvatarPhoto(
      img.encodeJpg(photo),
      name: 'IMG_0001.jpg',
      nativeImplementations: NativeImplementations.dummy,
    );

    final exif = img.decodeJpgExif(avatar.bytes);
    expect(exif?.imageIfd.sub.containsKey('gps') ?? false, isFalse);
    expect((avatar.width, avatar.height), (256, 512));
  });

  test('an avatar without a location is only shrunk', () async {
    final avatar = await prepareAvatarPhoto(
      img.encodeJpg(img.Image(width: 1024, height: 256)),
      name: 'IMG_0002.jpg',
      nativeImplementations: NativeImplementations.dummy,
    );

    expect((avatar.width, avatar.height), (512, 128));
  });
}
