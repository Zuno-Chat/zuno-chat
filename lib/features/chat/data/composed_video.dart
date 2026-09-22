class ComposedVideo {
  final String path;
  final String name;
  final String caption;
  final int? width;
  final int? height;
  final int? durationMs;

  const ComposedVideo({
    required this.path,
    required this.name,
    required this.caption,
    this.width,
    this.height,
    this.durationMs,
  });
}
