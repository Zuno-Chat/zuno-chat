import '../l10n/l10n.dart';

enum SendStage { compressing, uploading }

enum SendMediaKind { photo, video, file }

double? combinedSendProgress({
  required bool compresses,
  required SendStage stage,
  required double? fraction,
}) {
  final clamped = fraction?.clamp(0.0, 1.0);
  if (!compresses) return clamped ?? 0;
  return switch (stage) {
    SendStage.compressing => clamped == null ? null : clamped / 2,
    SendStage.uploading => 0.5 + (clamped ?? 0) / 2,
  };
}

String sendStageLabel(
  AppLocalizations l10n, {
  required SendMediaKind kind,
  required SendStage stage,
}) {
  return switch ((kind, stage)) {
    (SendMediaKind.photo, SendStage.compressing) => l10n.matrixCompressingPhoto,
    (SendMediaKind.photo, SendStage.uploading) => l10n.matrixUploadingPhoto,
    (SendMediaKind.video, SendStage.compressing) => l10n.matrixCompressingVideo,
    (SendMediaKind.video, SendStage.uploading) => l10n.matrixUploadingVideo,
    (SendMediaKind.file, _) => l10n.matrixUploadingFile,
  };
}
