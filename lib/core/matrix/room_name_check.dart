import '../l10n/l10n.dart';

String? roomNameError(AppLocalizations l10n, String name) {
  final normalized = name.toLowerCase().replaceAll('0', 'o');
  if (normalized.contains('zuno')) return l10n.matrixRoomNameNoZuno;
  return null;
}
