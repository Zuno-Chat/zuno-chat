import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../platform/platform_capabilities.dart';
import 'photo_location.dart';

const _channel = MethodChannel('zuno/image');

const _untouchedMimeTypes = {
  img.ImageFormat.jpg: 'image/jpeg',
  img.ImageFormat.png: 'image/png',
  img.ImageFormat.gif: 'image/gif',
  img.ImageFormat.webp: 'image/webp',
};

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

ResizedImage? _untouched(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    final mimeType = _untouchedMimeTypes[decoder?.format];
    if (decoder == null || mimeType == null) return null;
    final info = decoder.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
    final quarterTurned =
        orientation != null && orientation >= 5 && orientation <= 8;
    final stripped = withoutLocation(bytes);
    if (stripped == null) return null;
    return ResizedImage(
      bytes: stripped,
      width: quarterTurned ? info.height : info.width,
      height: quarterTurned ? info.width : info.height,
      mimeType: mimeType,
    );
  } catch (_) {
    return null;
  }
}

class NativeImageResizer {
  NativeImageResizer._({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  NativeImageResizer.forTest({PlatformCapabilities? capabilities})
    : this._(capabilities: capabilities);

  static final instance = NativeImageResizer._();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<ResizedImage?> resize(
    Uint8List bytes, {
    required int maxDimension,
    required int quality,
  }) async {
    if (!_capabilities.nativeImageResize) return compute(_untouched, bytes);
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
