import 'dart:math';
import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import '../async/background_work.dart';
import '../errors/caught_errors.dart';
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

  final blurhash = await blurhashInBackground((thumb ?? main).bytes);
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
const _jpegDecodeScales = [8, 4, 2];

Future<String?> blurhashInBackground(Uint8List bytes) async {
  try {
    return await runInBackground(
      () => blurhashOf(bytes),
      debugName: 'blurhash',
    );
  } catch (e, s) {
    reportCaught('decode an image for its blurhash', e, s);
    return null;
  }
}

@visibleForTesting
img.Image? decodeForBlurhash(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder is! img.JpegDecoder) return decoder?.decode(bytes);
  final info = decoder.startDecode(bytes);
  if (info == null) return null;
  final longEdge = max(info.width, info.height);
  final scale = _jpegDecodeScales.firstWhere(
    (scale) => (longEdge / scale).ceil() >= _blurhashSampleSize,
    orElse: () => 1,
  );
  return img.JpegDecoder(scale: scale).decode(bytes);
}

String? blurhashOf(Uint8List bytes) {
  final decoded = decodeForBlurhash(bytes);
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
