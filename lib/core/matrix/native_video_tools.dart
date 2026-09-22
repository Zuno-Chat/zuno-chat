import 'package:flutter/services.dart';

import 'native_image_resizer.dart';

const _channel = MethodChannel('zuno/video');

Future<Map<String, Object?>?> _invokeMap(
  String method,
  Map<String, Object?> arguments,
) async {
  try {
    return await _channel.invokeMapMethod<String, Object?>(method, arguments);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

class VideoProbe {
  final int width;
  final int height;
  final int? bitrate;
  final int? durationMs;
  final String? videoCodec;
  final String? audioCodec;

  const VideoProbe({
    required this.width,
    required this.height,
    this.bitrate,
    this.durationMs,
    this.videoCodec,
    this.audioCodec,
  });

  static VideoProbe? fromChannel(Map<String, Object?>? reply) {
    if (reply == null) return null;
    final width = reply['width'];
    final height = reply['height'];
    if (width is! int || height is! int || width <= 0 || height <= 0) {
      return null;
    }
    final bitrate = reply['bitrate'];
    final durationMs = reply['durationMs'];
    final videoCodec = reply['videoCodec'];
    final audioCodec = reply['audioCodec'];
    return VideoProbe(
      width: width,
      height: height,
      bitrate: bitrate is int ? bitrate : null,
      durationMs: durationMs is int ? durationMs : null,
      videoCodec: videoCodec is String ? videoCodec : null,
      audioCodec: audioCodec is String ? audioCodec : null,
    );
  }
}

class NativeVideoTools {
  NativeVideoTools._();
  NativeVideoTools.forTest();

  static final instance = NativeVideoTools._();

  Future<VideoProbe?> probe(String path) async =>
      VideoProbe.fromChannel(await _invokeMap('probe', {'path': path}));

  Future<bool> remux(String input, String output) async {
    try {
      return await _channel.invokeMethod<bool>('remux', {
            'input': input,
            'output': output,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<ResizedImage?> thumbnail(
    String path, {
    required int maxDimension,
    required int quality,
  }) async => ResizedImage.fromChannel(
    await _invokeMap('thumbnail', {
      'path': path,
      'maxDimension': maxDimension,
      'quality': quality,
    }),
  );
}
