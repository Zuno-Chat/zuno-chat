import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/forwarded_message.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/chat/data/discarded_sends.dart';
import 'package:zuno/features/chat/data/forward_uploads.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';
import 'package:zuno/features/chat/data/room_sender.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  late AttachmentServer server;
  late List<http.Request> requests;
  late List<String> said;
  late bool refuseSends;
  late bool refuseUploads;
  late bool uploadsOffline;
  late Completer<void>? holdSends;
  late Room source;
  late Room target;
  late RoomSender sender;

  Future<RoomSender> senderFor(Room room) async {
    final built = RoomSender(
      room: room,
      discarded: DiscardedSends(await SharedPreferences.getInstance()),
      reduceMediaSize: () => false,
      chatOpen: () => false,
      say: said.add,
    );
    addTearDown(built.dispose);
    return built;
  }

  setUp(() async {
    requests = [];
    said = [];
    refuseSends = false;
    refuseUploads = false;
    uploadsOffline = false;
    holdSends = null;
    silenceMethodChannels(['zuno/upload_service']);
    SharedPreferences.setMockInitialValues({});
    server = installAttachmentServer(database: SendingFakeDatabaseApi())
      ..respond = (request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/upload')) {
          if (uploadsOffline) throw const SocketException('offline');
          return refuseUploads
              ? http.Response(
                  jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'no'}),
                  400,
                )
              : http.Response(
                  jsonEncode({'content_uri': 'mxc://example.org/reuploaded'}),
                  200,
                );
        }
        if (path.endsWith('/config')) return http.Response('{}', 200);
        if (path.contains('/send/')) {
          await holdSends?.future;
          if (refuseSends) {
            return http.Response(
              jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'no'}),
              400,
            );
          }
        }
        if (path.contains('/send/') || path.contains('/redact/')) {
          return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
        }
        return null;
      };
    source = server.room..partial = false;
    target = buildTestRoom(server.client, id: '!target:example.org')
      ..partial = false;
    server.client.rooms.addAll([source, target]);
    sender = await senderFor(target);
  });

  Event media(String id, Map<String, Object?> content) => buildTestEvent(
    source,
    eventId: id,
    senderId: '@bob:example.org',
    status: EventStatus.synced,
    content: {'msgtype': MessageTypes.Image, 'body': '$id.jpg', ...content},
  );

  Event plain(String id, {Map<String, Object?> extra = const {}}) =>
      media(id, {'url': 'mxc://example.org/${id.substring(1)}', ...extra});

  Iterable<http.Request> requestsTo(String part) =>
      requests.where((r) => r.url.path.contains(part));

  Iterable<Map<String, Object?>> sentContents() => [
    for (final request in requestsTo('/send/'))
      jsonDecode(request.body) as Map<String, Object?>,
  ];

  List<Event> shownInTarget() {
    final shown = <Event>[];
    final sub = server.client.onTimelineEvent.stream
        .where((event) => event.room.id == target.id)
        .listen(shown.add);
    addTearDown(sub.cancel);
    return shown;
  }

  Event secretPhoto({bool thumbnailCached = true}) {
    final secret = media(r'$secret', {
      'file': encryptedFileContent(),
      'info': {
        'mimetype': 'image/jpeg',
        'w': 400,
        'h': 300,
        'thumbnail_file': encryptedFileContent(
          url: 'mxc://example.org/secret-thumb',
        ),
        'thumbnail_info': {'mimetype': 'image/png', 'w': 40, 'h': 30},
      },
    });
    AttachmentCache.instance.put(
      attachmentCacheKey(secret, thumbnail: false),
      Uint8List.fromList([1, 2, 3]),
    );
    if (thumbnailCached) {
      AttachmentCache.instance.put(
        attachmentCacheKey(secret, thumbnail: true),
        Uint8List.fromList([4, 5]),
      );
    }
    return secret;
  }

  test(
    'a forward reuses the file and sends the copy with the marker',
    () async {
      final failure = await sender.forward([plain(r'$photo')]);

      expect(failure, isNull);
      expect(requestsTo('/upload'), isEmpty);
      expect(sentContents().single['url'], 'mxc://example.org/photo');
      expect(sentContents().single[forwardedKey], isTrue);
      expect(
        requestsTo('/send/').single.url.pathSegments,
        contains('!target:example.org'),
      );
    },
  );

  test('encrypted media into an unencrypted chat is uploaded again as the '
      'decrypted bytes, and its key never appears', () async {
    final secret = secretPhoto();

    final failure = await sender.forward([secret]);

    expect(failure, isNull);
    final uploads = requestsTo('/upload').toList();
    expect(uploads.map((r) => r.bodyBytes), [
      [1, 2, 3],
      [4, 5],
    ]);
    expect(uploads.map((r) => r.headers['content-type']), [
      'image/jpeg',
      'image/png',
    ]);
    final sent = sentContents().single;
    expect(sent['url'], 'mxc://example.org/reuploaded');
    expect(sent['msgtype'], MessageTypes.Image);
    expect(sent[forwardedKey], isTrue);
    expect(sent.containsKey('file'), isFalse);
    final info = sent['info']! as Map;
    expect(info['thumbnail_url'], 'mxc://example.org/reuploaded');
    expect(info.containsKey('thumbnail_file'), isFalse);
    expect((info['w'], info['h']), (400, 300));
    expect(jsonEncode(sent), isNot(contains('original-key')));
    expect(secret.content['file'], isNotNull);
    expect((secret.content['info']! as Map)['thumbnail_file'], isNotNull);
  });

  test('a plain photo with an encrypted thumbnail keeps its link and uploads '
      'only the thumbnail', () async {
    final photo = media(r'$mixed', {
      'url': 'mxc://example.org/mixed',
      'info': {
        'mimetype': 'image/jpeg',
        'thumbnail_file': encryptedFileContent(
          url: 'mxc://example.org/mixed-thumb',
          key: 'thumbnail-key',
        ),
        'thumbnail_info': {'mimetype': 'image/png'},
      },
    });
    AttachmentCache.instance.put(
      attachmentCacheKey(photo, thumbnail: true),
      Uint8List.fromList([4, 5]),
    );

    final failure = await sender.forward([photo]);

    expect(failure, isNull);
    expect(requestsTo('/upload').single.bodyBytes, [4, 5]);
    final sent = sentContents().single;
    expect(sent['url'], 'mxc://example.org/mixed');
    expect(
      (sent['info']! as Map)['thumbnail_url'],
      'mxc://example.org/reuploaded',
    );
    expect(jsonEncode(sent), isNot(contains('thumbnail-key')));
  });

  test('forwarding to two unencrypted chats uploads it once and both use '
      'that upload', () async {
    final other = buildTestRoom(server.client, id: '!other:example.org')
      ..partial = false;
    server.client.rooms.add(other);
    final otherSender = await senderFor(other);
    final secret = secretPhoto();
    final uploads = ForwardUploads();

    final failures = await Future.wait([
      sender.forward([secret], uploads: uploads),
      otherSender.forward([secret], uploads: uploads),
    ]);

    expect(failures, [null, null]);
    expect(requestsTo('/upload'), hasLength(2));
    expect(sentContents(), hasLength(2));
    expect(
      sentContents().map((sent) => sent['url']),
      everyElement('mxc://example.org/reuploaded'),
    );
  });

  test('a thumbnail that cannot be fetched is left out, and the photo still '
      'goes', () async {
    final secret = secretPhoto(thumbnailCached: false);

    final failure = await sender.forward([secret]);

    expect(failure, isNull);
    final info = sentContents().single['info']! as Map;
    expect(info.containsKey('thumbnail_url'), isFalse);
    expect(info.containsKey('thumbnail_file'), isFalse);
    expect(info.containsKey('thumbnail_info'), isFalse);
  });

  test(
    'a forward that uploads keeps the upload alive in the background',
    () async {
      ambientCapabilities = capabilitiesLike(
        androidCapabilities,
        uploadForegroundService: true,
      );
      final service = recordChannel(const MethodChannel('zuno/upload_service'));

      await sender.forward([secretPhoto()]);

      final methods = service.calls.map((call) => call.method);
      expect(methods.first, 'start');
      expect(methods.last, 'stop');
    },
  );

  test('a forward whose upload fails waits in that chat for Retry, quietly, '
      'and Retry sends it', () async {
    refuseUploads = true;
    final secret = secretPhoto();

    expect(await sender.forward([secret]), isA<MatrixException>());

    expect(said, isEmpty);
    final failed = sender.failed.single;
    expect((failed as FailedForwardSend).event, same(secret));
    expect(sentContents(), isEmpty);

    refuseUploads = false;
    await sender.retry(failed);

    expect(sender.failed, isEmpty);
    expect(sentContents().single['url'], 'mxc://example.org/reuploaded');
  });

  test('a retried forward that fails offline says so and to check the '
      'connection, and waits for Retry again', () async {
    refuseUploads = true;
    await sender.forward([secretPhoto()]);

    uploadsOffline = true;
    await sender.retry(sender.failed.single);

    expect(said, ['Not sent. Check your connection and try again.']);
    expect(sender.failed, hasLength(1));
  });

  test('a retried forward the server refuses says only that it did not '
      'send', () async {
    refuseUploads = true;
    await sender.forward([secretPhoto()]);

    await sender.retry(sender.failed.single);

    expect(said, ['Not sent. Try again.']);
  });

  test(
    'a forward deleted while it sends is taken back once it lands',
    () async {
      holdSends = Completer();
      final shown = shownInTarget();
      final forwarding = sender.forward([plain(r'$photo')]);
      await pumpEventQueue();

      await sender.discardUnsent(shown.firstWhere((e) => e.status.isSending));
      holdSends!.complete();

      expect(await forwarding, isNull);
      await pumpEventQueue();
      expect(requestsTo('/redact/'), hasLength(1));
    },
  );

  test('deleting a forwarded gallery while it sends stops the rest', () async {
    holdSends = Completer();
    final shown = shownInTarget();
    final forwarding = sender.forward([
      plain(r'$g0'),
      plain(r'$g1'),
      plain(r'$g2'),
    ]);
    await pumpEventQueue();

    await sender.dropGalleries([shown.firstWhere((e) => e.status.isSending)]);
    holdSends!.complete();
    await forwarding;
    await pumpEventQueue();

    expect(sentContents(), hasLength(1));
    expect(requestsTo('/redact/'), hasLength(1));
  });

  test('a gallery goes out as a new gallery, in order', () async {
    final items = [
      plain(r'$g0', extra: galleryGroupContent(id: 'old', index: 0, count: 3)),
      plain(r'$g1', extra: galleryGroupContent(id: 'old', index: 1, count: 3)),
      plain(r'$g2', extra: galleryGroupContent(id: 'old', index: 2, count: 3)),
    ];

    final failure = await sender.forward(items);

    expect(failure, isNull);
    final groups = [
      for (final sent in sentContents()) sent[galleryGroupKey]! as Map,
    ];
    expect(groups.map((g) => g['index']), [0, 1, 2]);
    expect(groups.map((g) => g['count']).toSet(), {3});
    expect(groups.map((g) => g['id']).toSet(), hasLength(1));
    expect(groups.first['id'], isNot('old'));
    expect(sentContents().map((sent) => sent['url']), [
      'mxc://example.org/g0',
      'mxc://example.org/g1',
      'mxc://example.org/g2',
    ]);
  });

  test('a forward whose upload fails offline returns the connection '
      'error', () async {
    uploadsOffline = true;

    final failure = await sender.forward([secretPhoto()]);

    expect(failure, isA<SocketException>());
    expect(said, isEmpty);
  });

  test('a send that does not go returns that it did not, says nothing and '
      'reports nothing', () async {
    refuseSends = true;
    final logs = recordDebugPrints();

    final failure = await sender.forward([plain(r'$photo')]);

    expect(failure, isA<ForwardNotSent>());
    expect(said, isEmpty);
    expect(logs.where((line) => line.startsWith('zuno/caught:')), isEmpty);
  });
}
