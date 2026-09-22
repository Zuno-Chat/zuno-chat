import 'dart:math';
import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'media_processing_exception.dart';
import 'media_quality.dart';
import 'native_image_resizer.dart';
import 'sent_media_name.dart';

class PreparedImage {
  final MatrixImageFile file;
  final MatrixImageFile? thumbnail;

  const PreparedImage({required this.file, this.thumbnail});
}

MatrixImageFile matrixImageFile(
  ResizedImage image, {
  required String name,
  required String? blurhash,
}) => MatrixImageFile(
  bytes: image.bytes,
  name: name,
  mimeType: image.mimeType,
  width: image.width,
  height: image.height,
  blurhash: blurhash,
);

Future<PreparedImage> prepareImageForSend(
  Uint8List bytes, {
  required bool reduceMediaSize,
  NativeImageResizer? resizer,
  void Function(double fraction)? onProgress,
}) async {
  final native = resizer ?? NativeImageResizer.instance;
  final quality = imageJpegQuality(reduceMediaSize: reduceMediaSize);
  onProgress?.call(0);
  final main = await native.resize(
    bytes,
    maxDimension: imageShrinkMaxDimension(reduceMediaSize: reduceMediaSize),
    quality: quality,
  );
  if (main == null) {
    throw const MediaProcessingException('Cannot send this photo');
  }
  onProgress?.call(0.5);

  ResizedImage? thumb;
  if (max(main.width, main.height) > imageThumbnailMaxDimension) {
    thumb = await native.resize(
      bytes,
      maxDimension: imageThumbnailMaxDimension,
      quality: quality,
    );
    if (thumb != null && thumb.bytes.length >= main.bytes.length) thumb = null;
  }

  final blurhash = await compute(blurhashOf, (thumb ?? main).bytes);
  onProgress?.call(1);

  final name = sentPhotoName(main.mimeType);
  return PreparedImage(
    file: matrixImageFile(main, name: name, blurhash: blurhash),
    thumbnail: thumb == null
        ? null
        : matrixImageFile(thumb, name: name, blurhash: blurhash),
  );
}

const _blurhashSampleSize = 32;

String? blurhashOf(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final landscape = decoded.width >= decoded.height;
  final small = img.copyResize(
    decoded,
    width: landscape ? _blurhashSampleSize : null,
    height: landscape ? null : _blurhashSampleSize,
    interpolation: img.Interpolation.average,
  );
  return BlurHash.encode(small, numCompX: 4, numCompY: 3).hash;
}
