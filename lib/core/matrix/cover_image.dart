import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../files/file_system.dart';
import 'cached_attachment_image.dart';

const _widestCoverBox = 2;

int decodeWidth(BuildContext context, {double? shownAt}) =>
    ((shownAt ?? MediaQuery.sizeOf(context).width) *
            MediaQuery.devicePixelRatioOf(context))
        .round();

class MediaImage extends StatelessWidget {
  final ImageProvider image;
  final double? shownAt;

  MediaImage.memory(Uint8List bytes, {this.shownAt, super.key})
    : image = MemoryImage(bytes);

  MediaImage.file(String path, {this.shownAt, super.key})
    : image = FileImage(fileSystem.file(path));

  @override
  Widget build(BuildContext context) =>
      Image(image: _coverDecoded(context, image, shownAt), fit: BoxFit.cover);
}

Widget attachmentThumbnail(
  Event event, {
  required Widget placeholder,
  double? shownAt,
}) {
  return CachedAttachmentImage(
    event: event,
    thumbnail: true,
    placeholder: placeholder,
    fit: BoxFit.cover,
    image: (context, attachment) => _coverDecoded(context, attachment, shownAt),
  );
}

ImageProvider _coverDecoded(
  BuildContext context,
  ImageProvider image,
  double? shownAt,
) => CoverDecode(image, decodeWidth(context, shownAt: shownAt));

class CoverDecode extends ImageProvider<(Object, int)> {
  final ImageProvider image;
  final int side;

  const CoverDecode(this.image, this.side);

  @override
  Future<(Object, int)> obtainKey(ImageConfiguration configuration) =>
      image.obtainKey(configuration).then((key) => (key, side));

  @override
  ImageStreamCompleter loadImage(
    (Object, int) key,
    ImageDecoderCallback decode,
  ) =>
      image.loadImage(
        key.$1,
        (buffer, {getTargetSize}) => decode(buffer, getTargetSize: _coverSize),
      )..addEphemeralErrorListener(
        (_, _) => scheduleMicrotask(
          () => PaintingBinding.instance.imageCache.evict(key),
        ),
      );

  ui.TargetImageSize _coverSize(int width, int height) {
    final scale = [
      1.0,
      side / math.min(width, height),
      side * _widestCoverBox / math.max(width, height),
    ].reduce(math.min);
    return ui.TargetImageSize(
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoverDecode && other.image == image && other.side == side;

  @override
  int get hashCode => Object.hash(image, side);
}
