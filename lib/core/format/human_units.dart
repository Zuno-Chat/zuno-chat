String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatDuration(Duration duration) {
  final shown = duration.isNegative ? Duration.zero : duration;
  final seconds = shown.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (shown.inHours == 0) return '${shown.inMinutes}:$seconds';
  final minutes = shown.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${shown.inHours}:$minutes:$seconds';
}
