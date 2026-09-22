import 'dart:async';

import 'package:light_compressor/light_compressor.dart';

import 'media_processing_exception.dart';
import 'media_quality.dart';

const videoSendFailure = MediaProcessingException('Cannot send this video');

typedef VideoReencoder = Future<String> Function(
  String path, {
  required int? width,
  required int? height,
  required int bitrateMbps,
  void Function(double fraction)? onProgress,
});

Future<String> reencodeVideo(
  String path, {
  required int? width,
  required int? height,
  required int bitrateMbps,
  void Function(double fraction)? onProgress,
}) async {
  final encoderTarget = width != null && height != null
      ? toRawEncoderOrientation(
          target: (width: width, height: height),
          isPortrait: height > width,
        )
      : null;
  StreamSubscription<double>? progressSub;
  try {
    if (onProgress != null) {
      progressSub = LightCompressor().onProgressUpdated.listen(
        (percent) => onProgress((percent / 100).clamp(0.0, 1.0)),
      );
    }
    final result = await LightCompressor().compressVideo(
      path: path,
      videoQuality: VideoQuality.medium,
      android: AndroidConfig(isSharedStorage: false),
      ios: IOSConfig(saveInGallery: false),
      isMinBitrateCheckEnabled: false,
      video: Video(
        videoName: 'video_${DateTime.now().microsecondsSinceEpoch}',
        videoBitrateInMbps: bitrateMbps,
        videoWidth: encoderTarget?.width,
        videoHeight: encoderTarget?.height,
      ),
    );
    if (result is! OnSuccess) throw videoSendFailure;
    return result.destinationPath;
  } on MediaProcessingException {
    rethrow;
  } catch (_) {
    throw videoSendFailure;
  } finally {
    await progressSub?.cancel();
  }
}
