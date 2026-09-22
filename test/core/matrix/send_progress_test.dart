import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/send_progress.dart';

void main() {
  group('combinedSendProgress', () {
    test('an upload-only send maps upload progress straight through', () {
      expect(
        combinedSendProgress(
          compresses: false,
          stage: SendStage.uploading,
          fraction: 0.3,
        ),
        0.3,
      );
    });

    test('compression fills the first half', () {
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.compressing,
          fraction: 0.5,
        ),
        0.25,
      );
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.compressing,
          fraction: 1,
        ),
        0.5,
      );
    });

    test('upload fills the second half', () {
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.uploading,
          fraction: 0,
        ),
        0.5,
      );
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.uploading,
          fraction: 0.5,
        ),
        0.75,
      );
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.uploading,
          fraction: 1,
        ),
        1,
      );
    });

    test('unknown compression progress stays indeterminate', () {
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.compressing,
          fraction: null,
        ),
        isNull,
      );
    });

    test('unknown upload progress on an upload-only send reads as zero', () {
      expect(
        combinedSendProgress(
          compresses: false,
          stage: SendStage.uploading,
          fraction: null,
        ),
        0,
      );
    });

    test('fractions are clamped into range', () {
      expect(
        combinedSendProgress(
          compresses: true,
          stage: SendStage.uploading,
          fraction: 1.4,
        ),
        1,
      );
      expect(
        combinedSendProgress(
          compresses: false,
          stage: SendStage.uploading,
          fraction: -0.2,
        ),
        0,
      );
    });
  });

  group('sendStageLabel', () {
    test('names the media kind per stage', () {
      expect(
        sendStageLabel(kind: SendMediaKind.video, stage: SendStage.compressing),
        'Compressing video…',
      );
      expect(
        sendStageLabel(kind: SendMediaKind.video, stage: SendStage.uploading),
        'Uploading video…',
      );
      expect(
        sendStageLabel(kind: SendMediaKind.photo, stage: SendStage.compressing),
        'Compressing photo…',
      );
      expect(
        sendStageLabel(kind: SendMediaKind.photo, stage: SendStage.uploading),
        'Uploading photo…',
      );
    });

    test('a plain file only ever uploads', () {
      expect(
        sendStageLabel(kind: SendMediaKind.file, stage: SendStage.uploading),
        'Uploading…',
      );
      expect(
        sendStageLabel(kind: SendMediaKind.file, stage: SendStage.compressing),
        'Uploading…',
      );
    });
  });
}
