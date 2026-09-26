import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List? withoutLocation(Uint8List bytes) {
  final exif = img.decodeJpgExif(bytes);
  if (exif == null) return bytes;
  final gps = exif.imageIfd.sub.directories.remove('gps');
  if (gps == null) return bytes;
  return img.injectJpgExif(bytes, exif);
}
