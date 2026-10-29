import 'package:intl/intl.dart';

import '../l10n/l10n.dart';

String formatBytes(AppLocalizations l10n, int bytes) {
  if (bytes < 1024) return l10n.unitsBytes(bytes);
  final oneDecimal = NumberFormat('0.0', l10n.localeName);
  String rounded(double value) =>
      oneDecimal.format(double.parse(value.toStringAsFixed(1)));
  if (bytes < 1024 * 1024) return l10n.unitsKilobytes(rounded(bytes / 1024));
  return l10n.unitsMegabytes(rounded(bytes / (1024 * 1024)));
}

String formatDuration(Duration duration) {
  final shown = duration.isNegative ? Duration.zero : duration;
  final seconds = shown.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (shown.inHours == 0) return '${shown.inMinutes}:$seconds';
  final minutes = shown.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${shown.inHours}:$minutes:$seconds';
}

const detailSeparator = ' · ';

String joinDetails(Iterable<String> parts) => parts.join(detailSeparator);
