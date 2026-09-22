String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatClock(Duration duration) {
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${duration.inMinutes}:$seconds';
}
