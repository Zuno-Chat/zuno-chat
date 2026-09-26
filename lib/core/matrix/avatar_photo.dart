import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'media_processing_exception.dart';
import 'photo_location.dart';

const _avatarMaxDimension = 512;

Future<MatrixImageFile> prepareAvatarPhoto(
  Uint8List bytes, {
  required String name,
  required NativeImplementations nativeImplementations,
}) {
  final stripped = withoutLocation(bytes);
  if (stripped == null) {
    throw const MediaProcessingException('Cannot use this photo');
  }
  return MatrixImageFile.shrink(
    bytes: stripped,
    name: name,
    maxDimension: _avatarMaxDimension,
    nativeImplementations: nativeImplementations,
  );
}
