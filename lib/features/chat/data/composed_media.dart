sealed class ComposedMedia {
  final String path;
  final String name;
  final String caption;

  const ComposedMedia({
    required this.path,
    required this.name,
    required this.caption,
  });
}

class ComposedImage extends ComposedMedia {
  const ComposedImage({
    required super.path,
    required super.name,
    required super.caption,
  });
}

class ComposedVideo extends ComposedMedia {
  final int? width;
  final int? height;
  final int? durationMs;

  const ComposedVideo({
    required super.path,
    required super.name,
    required super.caption,
    this.width,
    this.height,
    this.durationMs,
  });
}
