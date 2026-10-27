import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/forwarded_message.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/features/chat/data/forwarding.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org', encrypting: true);
    room = buildTestRoom(client);
  });

  Event message(
    Map<String, Object?> content, {
    String id = r'$m',
    String type = EventTypes.Message,
    EventStatus status = EventStatus.synced,
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: '@bob:example.org',
    type: type,
    status: status,
    content: content,
  );

  Map<String, Object?> photo({Map<String, Object?> extra = const {}}) => {
    'msgtype': MessageTypes.Image,
    'body': 'sunset.jpg',
    'filename': 'sunset.jpg',
    'url': 'mxc://example.org/sunset',
    'info': {'mimetype': 'image/jpeg', 'w': 400, 'h': 300, 'size': 1234},
    ...extra,
  };

  test('photos, videos, files and stickers can be forwarded; voice messages '
      'and unsent media cannot', () {
    expect(canForward(message(photo())), isTrue);
    expect(
      canForward(
        message({
          'body': 'sticker',
          'url': 'mxc://example.org/sticker',
        }, type: EventTypes.Sticker),
      ),
      isTrue,
    );
    expect(
      canForward(
        message({
          'msgtype': MessageTypes.Audio,
          'body': 'voice',
          'url': 'mxc://example.org/voice',
          'org.matrix.msc3245.voice': <String, Object?>{},
        }),
      ),
      isFalse,
    );
    expect(canForward(message(photo(), status: EventStatus.sending)), isFalse);
  });

  group('forwardedContent', () {
    test('the copy keeps the media, caption, file name and info', () {
      final source = message(photo(extra: {'body': 'Sunset from the ridge'}));

      final copy = forwardedContent(source);

      expect(copy['msgtype'], MessageTypes.Image);
      expect(copy['url'], 'mxc://example.org/sunset');
      expect(copy['body'], 'Sunset from the ridge');
      expect(copy['filename'], 'sunset.jpg');
      expect(copy['info'], source.content['info']);
    });

    test('the copy carries the forwarded marker and no reply, edit, thread or '
        'mention', () {
      final source = message(
        photo(
          extra: {
            'body': '> <@carol:example.org> hello\n\nSunset from the ridge',
            'format': 'org.matrix.custom.html',
            'formatted_body': '<mx-reply>quoted</mx-reply>Sunset for <a href="https://matrix.to/#/@carol:example.org">Carol</a>',
            'm.relates_to': {
              'm.in_reply_to': {'event_id': r'$earlier'},
            },
            'm.new_content': {'body': 'edited'},
            'm.mentions': {
              'user_ids': ['@carol:example.org'],
            },
          },
        ),
      );

      final copy = forwardedContent(source);

      expect(copy[forwardedKey], isTrue);
      expect(copy['body'], 'Sunset from the ridge');
      expect(copy.containsKey('m.relates_to'), isFalse);
      expect(copy.containsKey('m.new_content'), isFalse);
      expect(copy.containsKey('formatted_body'), isFalse);
      expect(copy.containsKey('format'), isFalse);
      expect(copy['m.mentions'], <String, Object?>{});
      expect(jsonEncode(copy), isNot(contains('@carol')));
    });

    test('a forwarded gallery item gets the new gallery link and loses the '
        'old one', () {
      final source = message(
        photo(extra: galleryGroupContent(id: 'old', index: 2, count: 3)),
      );

      final copy = forwardedContent(
        source,
        gallery: const GalleryGroupRef(id: 'new', index: 0, count: 2),
      );
      final single = forwardedContent(source);

      expect(copy[galleryGroupKey], {'id': 'new', 'index': 0, 'count': 2});
      expect(single.containsKey(galleryGroupKey), isFalse);
    });

    test('the source content is left untouched', () {
      final source = message(photo(extra: {'m.mentions': <String, Object?>{}}));
      final before = jsonEncode(source.content);

      forwardedContent(source);

      expect(jsonEncode(source.content), before);
    });
  });

  test('encrypted media or an encrypted thumbnail going where it would not be '
      'encrypted needs an upload; every other pairing reuses the file', () {
    final secret = message({
      'msgtype': MessageTypes.Image,
      'body': 'secret.jpg',
      'file': encryptedFileContent(),
    });
    final secretThumbnail = message(
      photo(
        extra: {
          'info': {
            'mimetype': 'image/jpeg',
            'thumbnail_file': encryptedFileContent(),
          },
        },
      ),
    );
    final plain = message(photo());
    final private = namedRoom(
      client,
      '!private:example.org',
      'Private',
      encrypted: true,
    );
    final open = namedRoom(client, '!open:example.org', 'Open');
    final notEncryptingHere = namedRoom(
      buildTestClient(userId: '@me:example.org'),
      '!private:example.org',
      'Private',
      encrypted: true,
    );

    expect(forwardNeedsUpload(secret, open), isTrue);
    expect(forwardNeedsUpload(secretThumbnail, open), isTrue);
    expect(forwardNeedsUpload(secret, notEncryptingHere), isTrue);
    expect(forwardNeedsUpload(secret, private), isFalse);
    expect(forwardNeedsUpload(secretThumbnail, private), isFalse);
    expect(forwardNeedsUpload(plain, open), isFalse);
    expect(forwardNeedsUpload(plain, private), isFalse);
  });
}
