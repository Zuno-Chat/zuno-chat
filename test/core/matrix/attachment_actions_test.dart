import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:zuno/core/matrix/attachment_actions.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

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

  group('on a device', () {
    late AttachmentServer server;
    late DeviceFakes device;

    setUp(() {
      server = installAttachmentServer();
      device = installDeviceFakes();
    });

    Event photo([String eventId = r'$photo']) =>
        server.attachment(eventId: eventId, body: 'holiday.png');

    Event video() => server.attachment(
      eventId: r'$video',
      msgtype: MessageTypes.Video,
      body: 'clip.mp4',
      mimetype: 'video/mp4',
    );

    Event document({
      String mimetype = 'application/pdf',
      String body = 'report.pdf',
    }) => server.attachment(
      eventId: r'$document',
      msgtype: MessageTypes.File,
      body: body,
      mimetype: mimetype,
    );

    Event unnamed({
      String msgtype = MessageTypes.File,
      String body = 'report',
      String mimetype = 'application/pdf',
    }) => server.attachment(
      eventId: r'$unnamed',
      msgtype: msgtype,
      body: body,
      mimetype: mimetype,
    );

    List<String> sharedNames() => [
      for (final path in device.shared.single['paths']! as List)
        p.basename('$path'),
    ];

    group('saveAttachment', () {
      test('a photo goes to Photos under its own name', () async {
        expect(await saveAttachment(photo()), 'Saved to Photos');

        final call = device.gallery.single;
        expect(call.method, 'putImageBytes');
        expect((call.arguments as Map)['name'], 'holiday');
        expect((call.arguments as Map)['bytes'], server.served);
      });

      test('a photo saved twice is downloaded once', () async {
        await saveAttachment(photo());
        await saveAttachment(photo());

        expect(server.downloads, hasLength(1));
      });

      test('a video goes to Videos from a named copy, removed after', () async {
        expect(await saveAttachment(video()), 'Saved to Videos');

        final path = (device.gallery.single.arguments as Map)['path'] as String;
        expect(p.basename(path), 'clip.mp4');
        expect(device.galleryFilesPresent, [true]);
        for (var i = 0; i < 50 && File(path).existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(File(path).existsSync(), isFalse);
      });

      test('a file goes through the save dialog with its type', () async {
        expect(await saveAttachment(document()), 'Saved');

        final saved = device.picker.saved.single;
        expect(saved.fileName, 'report.pdf');
        expect(saved.mimeType, 'application/pdf');
        expect(saved.bytes, server.served);
      });

      test('a file saved twice is downloaded once', () async {
        await saveAttachment(document());
        await saveAttachment(document());

        expect(device.picker.saved, hasLength(2));
        expect(server.downloads, hasLength(1));
      });

      test(
        'a file named to leave its folder is saved as just the name',
        () async {
          await saveAttachment(document(body: '../../../etc/report.pdf'));

          expect(device.picker.saved.single.fileName, 'report.pdf');
        },
      );

      test('a file without a type is saved as plain bytes', () async {
        await saveAttachment(document(mimetype: ''));

        expect(device.picker.saved.single.mimeType, 'application/octet-stream');
      });

      test('closing the save dialog reports nothing', () async {
        device.picker.answer = null;

        expect(await saveAttachment(document()), isNull);
      });
    });

    test('saveAttachments counts only what landed', () async {
      final gone = photo(r'$gone');
      server.goneFromServer(gone);
      device.picker.answer = null;

      final saved = await saveAttachments([photo(), gone, document()]);

      expect(saved, 1);
      expect(device.gallery, hasLength(1));
    });

    group('shareAttachments', () {
      test('nothing to share opens no share sheet', () async {
        await shareAttachments(const []);

        expect(device.shared, isEmpty);
      });

      test('shares named copies with their types', () async {
        await shareAttachments([photo(), document()]);

        final shared = device.shared.single;
        expect(
          [for (final path in shared['paths']! as List) p.basename('$path')],
          ['holiday.png', 'report.pdf'],
        );
        expect(shared['mimeTypes'], ['image/png', 'application/pdf']);
      });

      test('items with the same name are shared as separate files', () async {
        await shareAttachments([
          server.attachment(eventId: r'$first', body: 'photo.jpg'),
          server.attachment(eventId: r'$second', body: 'photo.jpg'),
        ]);

        final paths = [
          for (final path in device.shared.single['paths']! as List) '$path',
        ];
        expect(paths.map(p.basename), ['photo.jpg', 'photo.jpg']);
        expect(paths.toSet(), hasLength(2));
        expect(paths.every((path) => File(path).existsSync()), isTrue);
      });

      test('the same item shared twice reuses its copy', () async {
        await shareAttachments([photo()]);
        await shareAttachments([photo()]);

        expect(device.shared[0]['paths'], device.shared[1]['paths']);
      });

      test('says it is preparing when something must download first', () async {
        var preparing = 0;

        await shareAttachments([photo()], onPreparing: () => preparing++);

        expect(preparing, 1);
      });

      test('shares at once when everything is already here', () async {
        final event = photo();
        AttachmentCache.instance.put(
          attachmentCacheKey(event, thumbnail: false),
          server.served,
        );
        var preparing = 0;

        await shareAttachments([event], onPreparing: () => preparing++);

        expect(preparing, 0);
        expect(device.shared, hasLength(1));
      });
    });

    group('where other apps go by the file extension', () {
      test('a shared file named without one gets it from its type', () async {
        await shareAttachments([unnamed()], capabilities: iosCapabilities);

        expect(sharedNames(), ['report.pdf']);
      });

      test('a video saved without one gets it from its type', () async {
        await saveAttachment(
          unnamed(
            msgtype: MessageTypes.Video,
            body: 'clip',
            mimetype: 'video/quicktime',
          ),
          capabilities: iosCapabilities,
        );

        final path = (device.gallery.single.arguments as Map)['path'] as String;
        expect(p.basename(path), 'clip.mov');
      });

      test('a file saved without one gets it from its type', () async {
        await saveAttachment(unnamed(), capabilities: iosCapabilities);

        expect(device.picker.saved.single.fileName, 'report.pdf');
      });

      test('a name with a dot but no known extension gets one', () async {
        await shareAttachments([
          unnamed(body: 'Mr. Smith report'),
        ], capabilities: iosCapabilities);

        expect(sharedNames(), ['Mr. Smith report.pdf']);
      });

      test('a name that has one keeps it', () async {
        await shareAttachments([
          unnamed(body: 'notes.txt'),
        ], capabilities: iosCapabilities);

        expect(sharedNames(), ['notes.txt']);
      });

      test('a file of unknown type keeps its name', () async {
        await shareAttachments([
          unnamed(mimetype: ''),
        ], capabilities: iosCapabilities);
        await saveAttachment(
          unnamed(mimetype: 'application/octet-stream'),
          capabilities: iosCapabilities,
        );

        expect(sharedNames(), ['report']);
        expect(device.picker.saved.single.fileName, 'report');
      });
    });

    test('where other apps go by the type, names are left alone', () async {
      final event = unnamed();

      await shareAttachments([event], capabilities: androidCapabilities);
      await saveAttachment(event, capabilities: androidCapabilities);

      expect(sharedNames(), ['report']);
      expect(device.picker.saved.single.fileName, 'report');
    });
  });
}
