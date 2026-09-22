import 'package:flutter/services.dart';

import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/send_progress.dart';
import 'composed_video.dart';

class PendingAttachmentSend {
  final String eventId;
  final Uint8List? previewBytes;
  final int? width;
  final int? height;
  final SendMediaKind kind;
  final SendStage stage;
  final double? stageProgress;

  PendingAttachmentSend({
    required this.eventId,
    this.previewBytes,
    this.width,
    this.height,
    required this.kind,
    SendStage? stage,
    this.stageProgress,
  }) : stage =
           stage ??
           (kind == SendMediaKind.file
               ? SendStage.uploading
               : SendStage.compressing);

  bool get compresses => kind != SendMediaKind.file;

  double? get progress => combinedSendProgress(
    compresses: compresses,
    stage: stage,
    fraction: stageProgress,
  );

  String get progressLabel => sendStageLabel(kind: kind, stage: stage);

  PendingAttachmentSend withStage(SendStage stage, double? stageProgress) =>
      PendingAttachmentSend(
        eventId: eventId,
        previewBytes: previewBytes,
        width: width,
        height: height,
        kind: kind,
        stage: stage,
        stageProgress: stageProgress,
      );

  PendingAttachmentSend withPreview(
    Uint8List bytes, {
    int? width,
    int? height,
  }) => PendingAttachmentSend(
    eventId: eventId,
    previewBytes: bytes,
    width: width ?? this.width,
    height: height ?? this.height,
    kind: kind,
    stage: stage,
    stageProgress: stageProgress,
  );
}

class FailedMediaSend {
  final GalleryGroupRef? gallery;
  final Uint8List? bytes;
  final ComposedVideo? video;
  final String? caption;

  const FailedMediaSend({
    required this.gallery,
    this.bytes,
    this.video,
    this.caption,
  });

  int get index => gallery?.index ?? 0;
}

bool pendingSendNeedsSyntheticTile({
  required String? pendingEventId,
  required Iterable<String> timelineEventIds,
}) {
  if (pendingEventId == null) return false;
  return !timelineEventIds.contains(pendingEventId);
}
