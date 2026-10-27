import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/send_progress.dart';
import 'composed_image.dart';
import 'composed_video.dart';

class PendingAttachmentSend {
  final String eventId;
  final Uint8List? previewBytes;
  final int? width;
  final int? height;
  final SendMediaKind kind;
  final bool compresses;
  final SendStage stage;
  final double? stageProgress;

  PendingAttachmentSend({
    required String eventId,
    Uint8List? previewBytes,
    int? width,
    int? height,
    required SendMediaKind kind,
    bool? compresses,
    SendStage? stage,
    double? stageProgress,
  }) : this._(
         eventId: eventId,
         previewBytes: previewBytes,
         width: width,
         height: height,
         kind: kind,
         compresses: compresses ?? kind != SendMediaKind.file,
         stage: stage,
         stageProgress: stageProgress,
       );

  PendingAttachmentSend._({
    required this.eventId,
    required this.previewBytes,
    required this.width,
    required this.height,
    required this.kind,
    required this.compresses,
    required SendStage? stage,
    required this.stageProgress,
  }) : stage =
           stage ?? (compresses ? SendStage.compressing : SendStage.uploading);

  double? get progress => combinedSendProgress(
    compresses: compresses,
    stage: stage,
    fraction: stageProgress,
  );

  String progressLabel(AppLocalizations l10n) =>
      sendStageLabel(l10n, kind: kind, stage: stage);

  PendingAttachmentSend withStage(SendStage stage, double? stageProgress) =>
      PendingAttachmentSend(
        eventId: eventId,
        previewBytes: previewBytes,
        width: width,
        height: height,
        kind: kind,
        compresses: compresses,
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
    compresses: compresses,
    stage: stage,
    stageProgress: stageProgress,
  );
}

class FailedMediaSend {
  final GalleryGroupRef? gallery;
  final ComposedImage? photo;
  final ComposedVideo? video;
  final Event? forward;

  const FailedMediaSend({
    required this.gallery,
    this.photo,
    this.video,
    this.forward,
  });

  int get index => gallery?.index ?? 0;

  String? get path => photo?.path ?? video?.path;
}

bool pendingSendNeedsSyntheticTile({
  required String? pendingEventId,
  required Iterable<String> timelineEventIds,
}) {
  if (pendingEventId == null) return false;
  return !timelineEventIds.contains(pendingEventId);
}
