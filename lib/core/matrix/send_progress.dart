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

String sendStageLabel({required SendMediaKind kind, required SendStage stage}) {
  final verb = stage == SendStage.compressing && kind != SendMediaKind.file
      ? 'Compressing'
      : 'Uploading';
  return switch (kind) {
    SendMediaKind.photo => '$verb photo…',
    SendMediaKind.video => '$verb video…',
    SendMediaKind.file => '$verb…',
  };
}
