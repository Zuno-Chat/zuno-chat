import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/send_progress.dart';
import 'package:zuno/features/chat/data/composed_image.dart';
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
      expect(file.progressLabel(englishLocalizations), 'Uploading…');
    });

    test('a photo sent as is starts uploading and counts the upload alone, '
        'through every change', () {
      final pending = PendingAttachmentSend(
        eventId: 't',
        kind: SendMediaKind.photo,
        compresses: false,
      );

      expect(pending.stage, SendStage.uploading);
      expect(pending.progressLabel(englishLocalizations), 'Uploading photo…');
      expect(pending.withStage(SendStage.uploading, 0.5).progress, 0.5);
      expect(
        pending
            .withPreview(Uint8List.fromList([1]))
            .withStage(SendStage.uploading, 0.25)
            .progress,
        0.25,
      );
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
      expect(pending.progressLabel(englishLocalizations), 'Uploading video…');
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
      expect(
        withPreview.progressLabel(englishLocalizations),
        'Compressing video…',
      );

      final resized = pending.withPreview(bytes, width: 80, height: 60);
      expect((resized.width, resized.height), (80, 60));
    });
  });

  test('a failed send sits at its place in the gallery, or first alone', () {
    const inGallery = FailedMediaSend(
      gallery: GalleryGroupRef(id: 'g', index: 2, count: 3),
      video: ComposedVideo(path: '/v.mp4', name: 'v.mp4', caption: ''),
    );
    const single = FailedMediaSend(
      gallery: null,
      photo: ComposedImage(path: '/p.jpg', name: 'p.jpg', caption: 'hi'),
    );

    expect(inGallery.index, 2);
    expect(single.index, 0);
  });

  test('a failed send names the copy it needs for a retry', () {
    const photo = FailedMediaSend(
      gallery: null,
      photo: ComposedImage(path: '/p.jpg', name: 'p.jpg', caption: ''),
    );
    const video = FailedMediaSend(
      gallery: null,
      video: ComposedVideo(path: '/v.mp4', name: 'v.mp4', caption: ''),
    );

    expect(photo.path, '/p.jpg');
    expect(video.path, '/v.mp4');
  });

  test('a pending send gets a synthetic tile only until its event is in the '
      'timeline', () {
    bool needsTile(String? pending, List<String> timeline) =>
        pendingSendNeedsSyntheticTile(
          pendingEventId: pending,
          timelineEventIds: timeline,
        );

    expect(needsTile(null, ['a', 'b']), isFalse);
    expect(needsTile('txid-1', ['a', 'b']), isTrue);
    expect(needsTile('txid-1', []), isTrue);
    expect(needsTile('txid-1', ['a', 'txid-1', 'b']), isFalse);
  });
}
