import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_actions.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/fake_files_channel.dart';
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

  group('savedMessage', () {
    test('says where a single save went', () {
      expect(
        savedMessage(englishLocalizations, event(MessageTypes.Image)),
        'Saved to Photos',
      );
      expect(
        savedMessage(englishLocalizations, event(MessageTypes.Video)),
        'Saved to Videos',
      );
      expect(
        savedMessage(englishLocalizations, event(MessageTypes.File)),
        'Saved',
      );
    });
  });

  group('savedSummary', () {
    test('reports a whole gallery saved', () {
      expect(
        savedSummary(englishLocalizations, saved: 4, total: 4),
        'Saved 4 items',
      );
      expect(
        savedSummary(englishLocalizations, saved: 1, total: 1),
        'Saved 1 item',
      );
    });

    test('is honest about a partial save', () {
      expect(
        savedSummary(englishLocalizations, saved: 3, total: 4),
        'Saved 3 of 4',
      );
    });

    test('says nothing landed when nothing did', () {
      expect(
        savedSummary(englishLocalizations, saved: 0, total: 4),
        'Could not save',
      );
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
        expect(await saveAttachment(photo()), isTrue);

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
        expect(await saveAttachment(video()), isTrue);

        final path = (device.gallery.single.arguments as Map)['path'] as String;
        expect(p.basename(path), 'clip.mp4');
        expect(device.galleryFilesPresent, [true]);
        await pumpEventQueue();
        expect(File(path).existsSync(), isFalse);
      });

      test(
        'a file is exported by Zuno from a named copy with its type, '
        'never read whole into the app, and the copy removed after',
        () async {
          expect(await saveAttachment(document()), isTrue);

          final exported = device.exported.single;
          expect(p.basename(exported.path), 'report.pdf');
          expect(exported.mimeType, 'application/pdf');
          expect(exported.bytes, server.served);
          expect(device.picker.saved, isEmpty);
          await pumpEventQueue();
          expect(File(exported.path).existsSync(), isFalse);
        },
      );

      test('a cancelled export saves nothing and leaves no copy', () async {
        device.exportAnswer = false;

        expect(await saveAttachment(document()), isFalse);
        final path = device.exported.single.path;
        await pumpEventQueue();
        expect(File(path).existsSync(), isFalse);
      });

      test('a failed export fails the save and leaves no copy', () async {
        final native = installFakeFilesChannel(
          reply: (_) => throw PlatformException(code: 'write_failed'),
        );

        await expectLater(
          saveAttachment(document()),
          throwsA(isA<PlatformException>()),
        );
        final path = (native.calls.single.arguments as Map)['path'] as String;
        await pumpEventQueue();
        expect(File(path).existsSync(), isFalse);
      });

      test('a file saved twice is downloaded once', () async {
        await saveAttachment(document());
        await saveAttachment(document());

        expect(device.exported, hasLength(2));
        expect(server.downloads, hasLength(1));
      });

      test(
        'a file named to leave its folder is saved as just the name',
        () async {
          await saveAttachment(document(body: '../../../etc/report.pdf'));

          expect(p.basename(device.exported.single.path), 'report.pdf');
        },
      );

      test('a file without a type is saved as plain bytes', () async {
        await saveAttachment(document(mimetype: ''));

        expect(device.exported.single.mimeType, 'application/octet-stream');
      });
    });

    test('saveAttachments counts only what landed', () async {
      final gone = photo(r'$gone');
      server.goneFromServer(gone);
      device.exportAnswer = false;

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

      test(
        'the same item shared twice is copied each time, downloaded once',
        () async {
          await shareAttachments([photo()]);
          await shareAttachments([photo()]);

          final paths = [
            for (final share in device.shared)
              '${(share['paths']! as List).single}',
          ];
          expect(paths.toSet(), hasLength(2));
          expect(paths.every((path) => File(path).existsSync()), isTrue);
          expect(server.downloads, hasLength(1));
        },
      );

      test(
        'saving a shared video leaves the copy the other app was given',
        () async {
          await shareAttachments([video()]);
          final shared = '${(device.shared.single['paths']! as List).single}';

          await saveAttachment(video());
          final saved =
              (device.gallery.single.arguments as Map)['path'] as String;
          await pumpEventQueue();

          expect(File(saved).existsSync(), isFalse);
          expect(File(shared).existsSync(), isTrue);
        },
      );

      test('says it is preparing when something must download first', () async {
        var preparing = 0;

        await shareAttachments([photo()], onPreparing: () => preparing++);

        expect(preparing, 1);
      });

      test('copies handed over live in the attachment cache', () async {
        await shareAttachments([photo()]);
        await saveAttachment(video());

        final cache = '${server.cacheDirectory.path}/attachment_cache';
        final shared = '${(device.shared.single['paths']! as List).single}';
        expect(p.isWithin(cache, shared), isTrue);
        expect(
          p.isWithin(
            cache,
            (device.gallery.single.arguments as Map)['path'] as String,
          ),
          isTrue,
        );
        expect(server.temporaryDirectory.listSync(recursive: true), isEmpty);
      });

      test('on Android, shares through Zuno itself', () async {
        await shareAttachments([photo()], capabilities: androidCapabilities);

        expect(device.sharePlus, isEmpty);
        expect(device.nativeShares, hasLength(1));
      });

      test('on iOS, shares through the share sheet', () async {
        await shareAttachments([photo()], capabilities: iosCapabilities);

        expect(device.nativeShares, isEmpty);
        expect(device.sharePlus, hasLength(1));
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
        expect(server.downloads, isEmpty);
      });
    });

    group('handed over where other apps go by the file extension', () {
      test('a shared file named without one gets it from its type', () async {
        await shareAttachments([unnamed()]);

        expect(sharedNames(), ['report.pdf']);
      });

      test('a video saved without one gets it from its type', () async {
        await saveAttachment(
          unnamed(
            msgtype: MessageTypes.Video,
            body: 'clip',
            mimetype: 'video/quicktime',
          ),
        );

        final path = (device.gallery.single.arguments as Map)['path'] as String;
        expect(p.basename(path), 'clip.mov');
      });

      test('a file saved without one gets it from its type', () async {
        await saveAttachment(unnamed());

        expect(p.basename(device.exported.single.path), 'report.pdf');
      });

      test('a name with a dot but no known extension gets one', () async {
        await shareAttachments([unnamed(body: 'Mr. Smith report')]);

        expect(sharedNames(), ['Mr. Smith report.pdf']);
      });

      test('a name that has one keeps it', () async {
        await shareAttachments([unnamed(body: 'notes.txt')]);

        expect(sharedNames(), ['notes.txt']);
      });

      test('a file of unknown type keeps its name', () async {
        await shareAttachments([unnamed(mimetype: '')]);
        await saveAttachment(unnamed(mimetype: 'application/octet-stream'));

        expect(sharedNames(), ['report']);
        expect(p.basename(device.exported.single.path), 'report');
      });
    });
  });
}
