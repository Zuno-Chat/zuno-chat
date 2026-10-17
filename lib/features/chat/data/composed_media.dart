import 'composed_image.dart';
import 'composed_video.dart';

sealed class ComposedMedia {
  const ComposedMedia();
}

class ComposedImageResult extends ComposedMedia {
  final ComposedImage image;
  const ComposedImageResult(this.image);
}

class ComposedVideoResult extends ComposedMedia {
  final ComposedVideo video;
  const ComposedVideoResult(this.video);
}
