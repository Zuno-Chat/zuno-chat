class MediaProcessingException implements Exception {
  final String message;

  const MediaProcessingException(this.message);

  @override
  String toString() => message;
}
