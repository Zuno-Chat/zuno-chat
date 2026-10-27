import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/painting.dart';
import 'package:matrix/matrix.dart';

import '../async/background_work.dart';
import 'media_size.dart';

const _blurhashKey = 'xyz.amorgan.blurhash';

const _longEdgePixels = 32;

class BlurhashImage extends ImageProvider<BlurhashImage> {
  final BlurHash _blurhash;
  final int width;
  final int height;

  const BlurhashImage._(this._blurhash, this.width, this.height);

  String get hash => _blurhash.hash;

  static BlurhashImage? of(Event event, {required bool thumbnail}) {
    final hash =
        event.infoMap.tryGet<String>(_blurhashKey) ??
        event.thumbnailInfoMap.tryGet<String>(_blurhashKey);
    final size =
        [
              if (thumbnail && event.hasThumbnail) event.thumbnailInfoMap,
              event.infoMap,
              event.thumbnailInfoMap,
            ]
            .map(
              (info) => mediaSize(info.tryGet<int>('w'), info.tryGet<int>('h')),
            )
            .nonNulls
            .firstOrNull;
    if (hash == null || size == null) return null;
    try {
      return BlurhashImage._(BlurHash.decode(hash), size.$1, size.$2);
    } on BlurHashDecodeException {
      return null;
    }
  }

  @override
  Future<BlurhashImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    BlurhashImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_paint());

  Future<ImageInfo> _paint() async {
    final scale = _longEdgePixels / math.max(width, height);
    final pixelWidth = math.max(1, (width * scale).round());
    final pixelHeight = math.max(1, (height * scale).round());
    final blurhash = _blurhash;
    final pixels = await runInBackground(
      () => blurhash.toImage(pixelWidth, pixelHeight).getBytes(),
      debugName: 'blurhash',
    );
    final painted = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      pixelWidth,
      pixelHeight,
      ui.PixelFormat.rgba8888,
      painted.complete,
    );
    return ImageInfo(image: await painted.future, scale: pixelWidth / width);
  }

  @override
  bool operator ==(Object other) =>
      other is BlurhashImage &&
      other.hash == hash &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(hash, width, height);
}
