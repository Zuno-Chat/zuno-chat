import 'dart:math';

import 'media_quality.dart';

const h264Codec = 'video/avc';
const aacCodec = 'audio/mp4a-latm';

const _remuxBitrateTolerance = 1.25;
const _bitsPerMegabit = 1000000;

sealed class VideoSendPlan {
  const VideoSendPlan();
}

class RemuxVideo extends VideoSendPlan {
  const RemuxVideo();
}

class ReencodeVideo extends VideoSendPlan {
  final int? targetWidth;
  final int? targetHeight;
  final int bitrateMbps;

  const ReencodeVideo({
    required this.targetWidth,
    required this.targetHeight,
    required this.bitrateMbps,
  });
}

int videoBitrateMbps({required int longEdge}) => longEdge >= 720 ? 2 : 1;

VideoSendPlan planVideoSend({
  required int? width,
  required int? height,
  required int? bitrate,
  required String? videoCodec,
  required String? audioCodec,
  required bool reduceMediaSize,
}) {
  final cap = videoLongEdge(reduceMediaSize: reduceMediaSize);
  if (width != null &&
      height != null &&
      width > 0 &&
      height > 0 &&
      max(width, height) <= cap) {
    final target = scaledToFit(width: width, height: height, maxLongEdge: cap);
    final targetMbps = videoBitrateMbps(
      longEdge: max(target.width, target.height),
    );
    final codecsRemuxable =
        videoCodec == h264Codec &&
        (audioCodec == null || audioCodec == aacCodec);
    final bitrateAcceptable =
        bitrate != null &&
        bitrate <= targetMbps * _bitsPerMegabit * _remuxBitrateTolerance;
    if (codecsRemuxable && bitrateAcceptable) return const RemuxVideo();
  }
  return planVideoReencode(
    width: width,
    height: height,
    bitrate: bitrate,
    reduceMediaSize: reduceMediaSize,
  );
}

ReencodeVideo planVideoReencode({
  required int? width,
  required int? height,
  required int? bitrate,
  required bool reduceMediaSize,
}) {
  final cap = videoLongEdge(reduceMediaSize: reduceMediaSize);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return ReencodeVideo(
      targetWidth: null,
      targetHeight: null,
      bitrateMbps: videoBitrateMbps(longEdge: cap),
    );
  }
  final target = scaledToFit(width: width, height: height, maxLongEdge: cap);
  final targetMbps = videoBitrateMbps(
    longEdge: max(target.width, target.height),
  );
  return ReencodeVideo(
    targetWidth: target.width,
    targetHeight: target.height,
    bitrateMbps: bitrate == null
        ? targetMbps
        : max(1, min(targetMbps, bitrate ~/ _bitsPerMegabit)),
  );
}
