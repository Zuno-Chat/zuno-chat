import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/notifications/message_notification_image.dart';
import 'package:zuno/core/notifications/message_notification_poster.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/notifications/notification_avatar_cache.dart';
import 'package:zuno/core/push/push_timing.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  const roomId = '!room:example.org';
  final roomNotificationId = messageNotificationIdFor(roomId);
  final avatarUrl = Uri.parse('mxc://x/alice');
  final bytes = Uint8List.fromList([7, 7]);
  late RecordedNotifications notifications;
  late Client client;
  late Directory dir;
  var fetches = 0;

  MessageNotificationContent content({Uri? avatar, bool photo = false}) =>
      MessageNotificationContent(
        roomId: roomId,
        title: 'Alice',
        body: photo ? 'a cat' : 'hi',
        text: photo ? 'a cat' : 'hi',
        eventId: r'$1',
        senderId: '@a:x',
        senderName: 'Alice',
        senderAvatarUrl: avatar,
        timestamp: DateTime.utc(2031),
        isPhoto: photo,
      );

  List<Map<String, Object?>> linesOf(ShownNotification n) =>
      ((n.android['styleInformation'] as Map)['messages'] as List)
          .cast<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();

  void showing() {
    notifications.active = [
      {'id': roomNotificationId, 'channelId': 'direct_messages', 'payload': ''},
    ];
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    client = buildTestClient();
    dir = await Directory.systemTemp.createTemp('avatars');
    addTearDown(() => dir.delete(recursive: true));
    NotificationAvatarCache.instance = NotificationAvatarCache(
      directory: () async => dir,
    );
    addTearDown(
      () => NotificationAvatarCache.instance = NotificationAvatarCache(),
    );
    fetches = 0;
  });

  Iterable<ShownNotification> roomPosts() =>
      notifications.shown.where((n) => n.id == roomNotificationId);

  Future<void> firstPost() async {
    for (var i = 0; i < 500 && roomPosts().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'posts the text first and refines with the avatar once fetched',
    () async {
      final fetched = Completer<Uint8List?>();
      final done = postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        fetchAvatar: (_, _) {
          fetches++;
          return fetched.future;
        },
      );
      await firstPost();
      expect(roomPosts(), hasLength(1));
      expect(roomPosts().single.android['largeIcon'], isNull);

      notifications.active = [
        {
          'id': roomNotificationId,
          'channelId': 'direct_messages',
          'payload': '',
        },
      ];
      fetched.complete(bytes);
      await done;

      expect(roomPosts(), hasLength(2));
      expect(roomPosts().last.android['largeIcon'], bytes);
      expect(roomPosts().last.android['onlyAlertOnce'], isTrue);
    },
  );

  test('where notifications show no sender avatars, no avatar is looked up, '
      'fetched or refined', () async {
    final appDir = await Directory.systemTemp.createTemp('app_avatars');
    addTearDown(() => appDir.delete(recursive: true));
    final appAvatars = DiskAttachmentCache.forTest(appDir);
    await appAvatars.put('avatar:$avatarUrl:small', bytes);

    await postMessageNotification(
      content(avatar: avatarUrl),
      client: client,
      appAvatars: appAvatars,
      capabilities: capabilitiesLike(
        androidCapabilities,
        notificationAvatars: false,
      ),
      fetchAvatar: (_, _) async {
        fetches++;
        return bytes;
      },
    );

    expect(fetches, 0);
    expect(roomPosts(), hasLength(1));
    expect(roomPosts().single.android['largeIcon'], isNull);
  });

  test('uses a cached avatar straight away without fetching', () async {
    await NotificationAvatarCache.instance.write(avatarUrl, bytes);

    await postMessageNotification(
      content(avatar: avatarUrl),
      client: client,
      fetchAvatar: (_, _) async {
        fetches++;
        return null;
      },
    );

    expect(roomPosts(), hasLength(1));
    expect(roomPosts().single.android['largeIcon'], bytes);
    expect(fetches, 0);
  });

  group('an avatar the app already keeps for the sender', () {
    late DiskAttachmentCache appAvatars;

    setUp(() async {
      final appDir = await Directory.systemTemp.createTemp('app-avatars');
      addTearDown(() => appDir.delete(recursive: true));
      appAvatars = DiskAttachmentCache.forTest(appDir);
    });

    test('is on the first post, with nothing fetched', () async {
      await appAvatars.put('avatar:$avatarUrl:small', bytes);

      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        appAvatars: appAvatars,
        fetchAvatar: (_, _) async {
          fetches++;
          return null;
        },
      );

      expect(roomPosts(), hasLength(1));
      expect(roomPosts().single.android['largeIcon'], bytes);
      expect(fetches, 0);
    });

    test('is kept for the notifications that follow', () async {
      await appAvatars.put('avatar:$avatarUrl:small', bytes);

      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        appAvatars: appAvatars,
      );

      expect(await NotificationAvatarCache.instance.read(avatarUrl), bytes);
    });

    test('of another size or another sender is not used', () async {
      await appAvatars.put('avatar:$avatarUrl:large', bytes);
      await appAvatars.put('avatar:mxc://x/bob:small', bytes);

      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        appAvatars: appAvatars,
        fetchAvatar: (_, _) async {
          fetches++;
          return null;
        },
      );

      expect(roomPosts().single.android['largeIcon'], isNull);
      expect(fetches, 1);
    });

    test('is not looked up once the notification has its own copy', () async {
      await NotificationAvatarCache.instance.write(avatarUrl, bytes);
      await appAvatars.put('avatar:$avatarUrl:small', Uint8List.fromList([1]));

      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        appAvatars: appAvatars,
      );

      expect(roomPosts().single.android['largeIcon'], bytes);
    });
  });

  test('a placeholder never fetches anything', () async {
    await postMessageNotification(
      content(avatar: avatarUrl),
      client: client,
      placeholder: true,
      fetchAvatar: (_, _) async {
        fetches++;
        return bytes;
      },
    );

    expect(roomPosts(), hasLength(1));
    expect(fetches, 0);
  });

  test('a failed avatar fetch leaves the text post standing', () async {
    await postMessageNotification(
      content(avatar: avatarUrl),
      client: client,
      fetchAvatar: (_, _) async => null,
    );

    expect(roomPosts(), hasLength(1));
  });

  group('with the refinement handed back', () {
    test('returns after the first post and refines on its own', () async {
      final fetched = Completer<Uint8List?>();
      final refinements = <Future<void>>[];

      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        fetchAvatar: (_, _) => fetched.future,
        onRefining: refinements.add,
      );

      expect(roomPosts(), hasLength(1));
      expect(refinements, hasLength(1));

      showing();
      fetched.complete(bytes);
      await refinements.single;

      expect(roomPosts(), hasLength(2));
      expect(roomPosts().last.android['largeIcon'], bytes);
    });

    test('a refinement that throws ends quietly', () async {
      final refinements = <Future<void>>[];

      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        fetchAvatar: (_, _) async => throw StateError('offline'),
        onRefining: refinements.add,
      );

      await expectLater(refinements.single, completes);
      expect(roomPosts(), hasLength(1));
    });

    test('nothing to refine hands nothing back', () async {
      final refinements = <Future<void>>[];

      await postMessageNotification(
        content(),
        client: client,
        onRefining: refinements.add,
      );
      await postMessageNotification(
        content(avatar: avatarUrl),
        client: client,
        placeholder: true,
        onRefining: refinements.add,
      );

      expect(refinements, isEmpty);
    });
  });

  test('a sender without an avatar is posted once, no fetch', () async {
    await postMessageNotification(
      content(),
      client: client,
      fetchAvatar: (_, _) async {
        fetches++;
        return bytes;
      },
    );

    expect(roomPosts(), hasLength(1));
    expect(fetches, 0);
  });

  test('the first post records where its time went', () async {
    final timing = PushTiming('test', elapsedMs: () => 0);

    await postMessageNotification(content(), client: client, timing: timing);

    expect(
      timing.report(),
      allOf([
        contains('init='),
        contains('prefs='),
        contains('thread='),
        contains('sound='),
        contains('avatars='),
        contains('shortcut='),
        contains('show='),
        contains('store='),
      ]),
    );
  });

  group('photos', () {
    final thumb = NotificationImage(
      bytes: Uint8List.fromList([1, 2]),
      mimeType: 'image/jpeg',
    );

    test(
      'posts the caption first, then refines the line with its thumbnail',
      () async {
        final fetched = Completer<NotificationImage?>();
        final published = <String>[];
        final done = postMessageNotification(
          content(photo: true),
          client: client,
          fetchImage: () => fetched.future,
          publishImage: (image) async {
            published.add(image.mimeType);
            return 'content://zuno/thumb';
          },
        );
        await firstPost();
        expect(roomPosts(), hasLength(1));
        expect(linesOf(roomPosts().single).single['dataUri'], isNull);

        showing();
        fetched.complete(thumb);
        await done;

        expect(roomPosts(), hasLength(2));
        final line = linesOf(roomPosts().last).single;
        expect(line['text'], 'a cat');
        expect(line['dataUri'], 'content://zuno/thumb');
        expect(line['dataMimeType'], 'image/jpeg');
        expect(published, ['image/jpeg']);
        expect(roomPosts().last.android['onlyAlertOnce'], isTrue);
      },
    );

    test('a text message never fetches an image', () async {
      await postMessageNotification(
        content(),
        client: client,
        fetchImage: () async {
          fetches++;
          return thumb;
        },
        publishImage: (_) async => 'content://zuno/thumb',
      );

      expect(fetches, 0);
      expect(roomPosts(), hasLength(1));
    });

    test(
      'a thumbnail that cannot be published leaves the caption standing',
      () async {
        await postMessageNotification(
          content(photo: true),
          client: client,
          fetchImage: () async => thumb,
          publishImage: (_) async => null,
        );

        expect(roomPosts(), hasLength(1));
      },
    );

    test('a placeholder never fetches an image', () async {
      await postMessageNotification(
        content(photo: true),
        client: client,
        placeholder: true,
        fetchImage: () async {
          fetches++;
          return thumb;
        },
        publishImage: (_) async => 'content://zuno/thumb',
      );

      expect(fetches, 0);
    });
  });
}
