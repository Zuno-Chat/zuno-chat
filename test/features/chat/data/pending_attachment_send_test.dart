import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/send_progress.dart';
import 'package:zuno/features/chat/data/composed_video.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';

void main() {
  group('PendingAttachmentSend', () {
    test('media starts compressing, a file starts uploading', () {
      expect(
        PendingAttachmentSend(eventId: 't', kind: SendMediaKind.photo).stage,
        SendStage.compressing,
      );
      final file = PendingAttachmentSend(
        eventId: 't',
        kind: SendMediaKind.file,
      );
      expect(file.stage, SendStage.uploading);
      expect(file.compresses, isFalse);
      expect(file.progress, 0);
      expect(file.progressLabel, 'Uploading…');
    });

    test('a stage change keeps the preview and reports combined progress', () {
      final preview = Uint8List.fromList([1, 2, 3]);
      final pending = PendingAttachmentSend(
        eventId: 't',
        previewBytes: preview,
        width: 40,
        height: 30,
        kind: SendMediaKind.video,
      ).withStage(SendStage.uploading, 0.5);

      expect(pending.previewBytes, same(preview));
      expect((pending.width, pending.height), (40, 30));
      expect(pending.progress, 0.75);
      expect(pending.progressLabel, 'Uploading video…');
    });

    test('a preview arriving later keeps the stage and known size', () {
      final pending = PendingAttachmentSend(
        eventId: 't',
        width: 40,
        height: 30,
        kind: SendMediaKind.video,
        stageProgress: 0.4,
      );
      final bytes = Uint8List.fromList([9]);

      final withPreview = pending.withPreview(bytes);
      expect(withPreview.previewBytes, same(bytes));
      expect((withPreview.width, withPreview.height), (40, 30));
      expect(withPreview.stage, SendStage.compressing);
      expect(withPreview.stageProgress, 0.4);
      expect(withPreview.progressLabel, 'Compressing video…');

      final resized = pending.withPreview(bytes, width: 80, height: 60);
      expect((resized.width, resized.height), (80, 60));
    });
  });

  group('FailedMediaSend', () {
    test('sits at its place in the gallery', () {
      const failed = FailedMediaSend(
        gallery: GalleryGroupRef(id: 'g', index: 2, count: 3),
        video: ComposedVideo(path: '/v.mp4', name: 'v.mp4', caption: ''),
      );
      expect(failed.index, 2);
    });

    test('a single send sits first', () {
      final failed = FailedMediaSend(
        gallery: null,
        bytes: Uint8List(0),
        caption: 'hi',
      );
      expect(failed.index, 0);
    });
  });
}
