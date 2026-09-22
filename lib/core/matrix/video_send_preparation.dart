import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'image_send_preparation.dart' show blurhashOf, matrixImageFile;
import 'media_quality.dart';
import 'native_image_resizer.dart';
import 'native_video_tools.dart';
import 'sent_media_name.dart';
import 'video_compression.dart';
import 'video_send_plan.dart';

const _thumbnailName = 'thumbnail.jpg';

class PreparedVideo {
  final MatrixVideoFile file;
  final MatrixImageFile? thumbnail;

  const PreparedVideo({required this.file, this.thumbnail});
}

typedef _Thumbnail = ({ResizedImage image, String? blurhash});

Future<_Thumbnail?> _loadThumbnail(
  NativeVideoTools native,
  String path, {
  required int quality,
  required void Function(ResizedImage thumbnail)? onThumbnail,
}) async {
  try {
    final image = await native.thumbnail(
      path,
      maxDimension: imageThumbnailMaxDimension,
      quality: quality,
    );
    if (image == null) return null;
    onThumbnail?.call(image);
    return (image: image, blurhash: await compute(blurhashOf, image.bytes));
  } catch (_) {
    return null;
  }
}

Future<PreparedVideo> prepareVideoForSend(
  String path, {
  required bool reduceMediaSize,
  int? fallbackWidth,
  int? fallbackHeight,
  int? fallbackDurationMs,
  NativeVideoTools? tools,
  VideoReencoder? reencoder,
  Directory? workDir,
  void Function(ResizedImage thumbnail)? onThumbnail,
  void Function(double fraction)? onProgress,
}) async {
  final native = tools ?? NativeVideoTools.instance;
  onProgress?.call(0);
  final probe = await native.probe(path);
  final width = probe?.width ?? fallbackWidth;
  final height = probe?.height ?? fallbackHeight;

  final thumbnail = _loadThumbnail(
    native,
    path,
    quality: imageJpegQuality(reduceMediaSize: reduceMediaSize),
    onThumbnail: onThumbnail,
  );

  final plan = planVideoSend(
    width: width,
    height: height,
    bitrate: probe?.bitrate,
    videoCodec: probe?.videoCodec,
    audioCodec: probe?.audioCodec,
    reduceMediaSize: reduceMediaSize,
  );
  final dir = workDir ?? await getTemporaryDirectory();
  String? output;
  var outWidth = width;
  var outHeight = height;
  try {
    final reencode = reencoder ?? reencodeVideo;
    Future<void> reencodeInto(ReencodeVideo plan) async {
      output = await reencode(
        path,
        width: plan.targetWidth,
        height: plan.targetHeight,
        bitrateMbps: plan.bitrateMbps,
        onProgress: onProgress,
      );
      outWidth = plan.targetWidth ?? width;
      outHeight = plan.targetHeight ?? height;
    }

    switch (plan) {
      case RemuxVideo():
        final remuxed = p.join(
          dir.path,
          'video_send_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        if (await native.remux(path, remuxed)) {
          output = remuxed;
        } else {
          await reencodeInto(
            planVideoReencode(
              width: width,
              height: height,
              bitrate: null,
              reduceMediaSize: reduceMediaSize,
            ),
          );
        }
      case ReencodeVideo():
        await reencodeInto(plan);
    }
    final bytes = await File(output!).readAsBytes();
    final thumb = await thumbnail;
    onProgress?.call(1);
    return PreparedVideo(
      file: MatrixVideoFile(
        bytes: bytes,
        name: sentVideoName,
        width: outWidth,
        height: outHeight,
        duration: probe?.durationMs ?? fallbackDurationMs,
      ),
      thumbnail: thumb == null
          ? null
          : matrixImageFile(
              thumb.image,
              name: _thumbnailName,
              blurhash: thumb.blurhash,
            ),
    );
  } finally {
    final produced = output;
    if (produced != null) {
      final file = File(produced);
      unawaited(file.delete().catchError((_) => file));
    }
  }
}
