int imageShrinkMaxDimension({required bool reduceMediaSize}) =>
    reduceMediaSize ? 720 : 1080;

int videoLongEdge({required bool reduceMediaSize}) =>
    reduceMediaSize ? 480 : 720;

({int width, int height}) scaledToFit({
  required int width,
  required int height,
  required int maxLongEdge,
}) {
  if (width <= 0 || height <= 0) return (width: width, height: height);
  final longEdge = width > height ? width : height;
  if (longEdge <= maxLongEdge) {
    return (width: _evenFloor(width), height: _evenFloor(height));
  }
  final scale = maxLongEdge / longEdge;
  return (
    width: _evenFloor((width * scale).round()),
    height: _evenFloor((height * scale).round()),
  );
}

int _evenFloor(int value) => value - (value % 2);

({int width, int height}) toRawEncoderOrientation({
  required ({int width, int height}) target,
  required bool isPortrait,
}) => isPortrait
    ? (width: target.height, height: target.width)
    : (width: target.width, height: target.height);

({int width, int height})? encoderTarget({
  required int? width,
  required int? height,
  required bool? rotated,
}) => width == null || height == null
    ? null
    : toRawEncoderOrientation(
        target: (width: width, height: height),
        isPortrait: rotated ?? height > width,
      );

int imageJpegQuality({required bool reduceMediaSize}) =>
    reduceMediaSize ? 75 : 85;

const imageThumbnailMaxDimension = 800;

({double? maxDimension, int? quality}) pickerImageLimits({
  required bool nativeImageResize,
  required bool reduceMediaSize,
}) => nativeImageResize
    ? (maxDimension: null, quality: null)
    : (
        maxDimension: imageShrinkMaxDimension(reduceMediaSize: reduceMediaSize)
            .toDouble(),
        quality: imageJpegQuality(reduceMediaSize: reduceMediaSize),
      );
