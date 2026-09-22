import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/image');

class ResizedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final String mimeType;

  const ResizedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.mimeType,
  });

  static ResizedImage? fromChannel(Map<String, Object?>? reply) {
    if (reply == null) return null;
    final bytes = reply['bytes'];
    final width = reply['width'];
    final height = reply['height'];
    final mimeType = reply['mimeType'];
    if (bytes is! Uint8List ||
        width is! int ||
        height is! int ||
        mimeType is! String) {
      return null;
    }
    return ResizedImage(
      bytes: bytes,
      width: width,
      height: height,
      mimeType: mimeType,
    );
  }
}

class NativeImageResizer {
  NativeImageResizer._();
  NativeImageResizer.forTest();

  static final instance = NativeImageResizer._();

  Future<ResizedImage?> resize(
    Uint8List bytes, {
    required int maxDimension,
    required int quality,
  }) async {
    final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>('resize', {
        'bytes': bytes,
        'maxDimension': maxDimension,
        'quality': quality,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    return ResizedImage.fromChannel(result);
  }
}
