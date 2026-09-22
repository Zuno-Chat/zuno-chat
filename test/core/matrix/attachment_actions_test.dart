import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/attachment_actions.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
  });

  Event event(String msgtype) => buildTestEvent(
    room,
    eventId: 'e1',
    senderId: '@me:example.org',
    content: {'msgtype': msgtype, 'body': 'file'},
  );

  group('attachmentSaveTarget', () {
    test('sends photos and stickers to the photo gallery', () {
      expect(
        attachmentSaveTarget(event(MessageTypes.Image)),
        AttachmentSaveTarget.photos,
      );
      expect(
        attachmentSaveTarget(event(MessageTypes.Sticker)),
        AttachmentSaveTarget.photos,
      );
    });

    test('sends videos to the video gallery', () {
      expect(
        attachmentSaveTarget(event(MessageTypes.Video)),
        AttachmentSaveTarget.videos,
      );
    });

    test('sends anything else through the file picker', () {
      expect(
        attachmentSaveTarget(event(MessageTypes.File)),
        AttachmentSaveTarget.file,
      );
      expect(
        attachmentSaveTarget(event(MessageTypes.Audio)),
        AttachmentSaveTarget.file,
      );
    });
  });

  group('savedSummary', () {
    test('reports a whole gallery saved', () {
      expect(savedSummary(saved: 4, total: 4), 'Saved 4 items');
      expect(savedSummary(saved: 1, total: 1), 'Saved 1 item');
    });

    test('is honest about a partial save', () {
      expect(savedSummary(saved: 3, total: 4), 'Saved 3 of 4');
    });

    test('says nothing landed when nothing did', () {
      expect(savedSummary(saved: 0, total: 4), 'Could not save');
    });
  });

  group('safeAttachmentFileName', () {
    test('leaves an ordinary filename alone', () {
      expect(safeAttachmentFileName('holiday.jpg'), 'holiday.jpg');
    });

    test('collapses a traversal attempt to its basename', () {
      expect(safeAttachmentFileName('../../databases/zuno.db'), 'zuno.db');
    });

    test('collapses an absolute path', () {
      expect(
        safeAttachmentFileName('/data/data/im.zuno.chat/shared_prefs/x.xml'),
        'x.xml',
      );
    });

    test('handles Windows-style separators too', () {
      expect(safeAttachmentFileName(r'..\..\zuno.db'), 'zuno.db');
    });

    test('falls back for names that are only traversal or empty', () {
      expect(safeAttachmentFileName('..'), 'file');
      expect(safeAttachmentFileName('.'), 'file');
      expect(safeAttachmentFileName(''), 'file');
      expect(safeAttachmentFileName('   '), 'file');
      expect(safeAttachmentFileName('/'), 'file');
    });

    test('strips control characters, NUL included', () {
      expect(safeAttachmentFileName('a\u0000b\u001fc.png'), 'abc.png');
    });

    test('caps length but keeps the extension', () {
      final name = safeAttachmentFileName('${'a' * 300}.png');
      expect(name.length, lessThanOrEqualTo(64));
      expect(name, endsWith('.png'));
    });
  });
}
