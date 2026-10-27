import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/mxc_avatar.dart';
import 'package:zuno/core/matrix/mxc_avatar_image.dart';
import 'package:zuno/core/ui/zuno_colors.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/pump_until.dart';

const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));
  final mxc = Uri.parse('mxc://example.org/abc');

  late List<http.Request> mediaRequests;
  late http.Response Function() mediaResponse;
  late Client client;
  late Directory dir;
  late DiskAttachmentCache disk;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PaintingBinding.instance.imageCache.clear();
    mediaRequests = [];
    mediaResponse = () => http.Response.bytes(png, 200);
    client = buildTestClient(
      userId: '@me:example.org',
      database: MediaCapableFakeDatabaseApi(),
      httpClient: FakeHttpClient((request) async {
        if (request.url.pathSegments.last == 'versions') {
          return http.Response(
            jsonEncode({
              'versions': ['v1.11'],
            }),
            200,
          );
        }
        mediaRequests.add(request);
        return mediaResponse();
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    dir = Directory.systemTemp.createTempSync('zuno_avatar');
    disk = DiskAttachmentCache.forTest(dir);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async =>
              call.method == 'getApplicationCacheDirectory' ? dir.path : null,
        );
  });

  tearDown(() async {
    await DiskAttachmentCache.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    dir.deleteSync(recursive: true);
  });

  MxcAvatarImage provider(AvatarBucket bucket) =>
      MxcAvatarImage(client: client, mxc: mxc, bucket: bucket, disk: disk);

  Uri uniqueMxc() =>
      Uri.parse('mxc://example.org/${clock.now().microsecondsSinceEpoch}');

  bool loadFailed(Uri address) =>
      mediaRequests.isNotEmpty &&
      !PaintingBinding.instance.imageCache
          .statusForKey(
            MxcAvatarImage(
              client: client,
              mxc: address,
              bucket: AvatarBucket.small,
            ),
          )
          .tracked;

  Widget host(Uri? avatarUrl) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MxcAvatar(
        client: client,
        avatarUrl: avatarUrl,
        fallbackText: 'maya',
        toneSeed: '@maya:zuno.chat',
      ),
    ),
  );

  test('the bucket follows the diameter', () {
    expect(AvatarBucket.forDiameter(32), AvatarBucket.small);
    expect(AvatarBucket.forDiameter(56), AvatarBucket.small);
    expect(AvatarBucket.forDiameter(56.5), AvatarBucket.large);
    expect(AvatarBucket.forDiameter(112), AvatarBucket.large);
  });

  testWidgets('two equal providers cost one request, at the small size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final info = await resolveImage(provider(AvatarBucket.small));
      await resolveImage(provider(AvatarBucket.small));

      expect(info.image.width, 1);
      expect(mediaRequests, hasLength(1));
      final query = mediaRequests.single.url.queryParameters;
      expect(query['width'], '96');
      expect(query['height'], '96');
      expect(query['method'], 'crop');
      expect(
        mediaRequests.single.headers['authorization'],
        'Bearer test-token',
      );
    });
  });

  testWidgets('the large bucket asks for a 320 scaled thumbnail', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await resolveImage(provider(AvatarBucket.large));

      final query = mediaRequests.single.url.queryParameters;
      expect(query['width'], '320');
      expect(query['method'], 'scale');
    });
  });

  testWidgets('a fresh image cache reads the avatar from disk', (tester) async {
    await tester.runAsync(() async {
      await resolveImage(provider(AvatarBucket.small));
      PaintingBinding.instance.imageCache.clear();
      await resolveImage(provider(AvatarBucket.small));

      expect(mediaRequests, hasLength(1));
    });
  });

  testWidgets('a 404 is an error, and the next try asks again', (tester) async {
    await tester.runAsync(() async {
      mediaResponse = () => http.Response('', 404);
      await expectLater(
        resolveImage(provider(AvatarBucket.small)),
        throwsA(anything),
      );

      mediaResponse = () => http.Response.bytes(png, 200);
      await resolveImage(provider(AvatarBucket.small));

      expect(mediaRequests, hasLength(2));
    });
  });

  testWidgets('bytes that do not decode are dropped from disk', (tester) async {
    await tester.runAsync(() async {
      mediaResponse = () => http.Response.bytes([1, 2, 3], 200);
      await expectLater(
        resolveImage(provider(AvatarBucket.small)),
        throwsA(anything),
      );

      expect(await disk.get('avatar:$mxc:small', expires: false), isNull);
    });
  });

  testWidgets('no address shows the ink initial on a tone, and asks nothing', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));

    expect(find.text('M'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, avatarToneFor('@maya:zuno.chat'));
    expect(avatar.foregroundColor, zunoInk);
    expect(avatar.foregroundImage, isNull);
    expect(mediaRequests, isEmpty);
  });

  testWidgets('the initial scales with the avatar', (tester) async {
    Future<double?> initialSize(double radius) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MxcAvatar(
            client: client,
            avatarUrl: null,
            fallbackText: 'maya',
            toneSeed: '@maya:zuno.chat',
            radius: radius,
          ),
        ),
      );
      return tester.widget<Text>(find.text('M')).style?.fontSize;
    }

    expect(await initialSize(26), closeTo(19.76, 0.01));
    expect(await initialSize(16), closeTo(12.16, 0.01));
    expect(await initialSize(56), closeTo(42.56, 0.01));
  });

  testWidgets('bytes that do not decode keep the initial and throw nothing', (
    tester,
  ) async {
    mediaResponse = () => http.Response.bytes([1, 2, 3], 200);
    final address = uniqueMxc();
    await tester.pumpWidget(host(address));
    await pumpUntil(
      tester,
      () => loadFailed(address),
      reason: 'the avatar to fail decoding',
    );
    await tester.pump();

    expect(find.text('M'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(mediaRequests, hasLength(1));
  });

  testWidgets('a rebuild does not ask again', (tester) async {
    final address = uniqueMxc();
    await tester.pumpWidget(host(address));
    await pumpUntil(tester, () => !shows('M'), reason: 'the avatar to show');
    await tester.pumpWidget(host(address));
    await tester.pump();

    expect(mediaRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a community photo is clipped to a rounded square, not a '
      'circle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MxcAvatar(
            client: client,
            avatarUrl: uniqueMxc(),
            fallbackText: 'Climbing club',
            toneSeed: '!climbing:zuno.chat',
            shape: AvatarShape.roundedSquare,
          ),
        ),
      ),
    );

    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(ClipOval), findsNothing);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('blank text falls back to a question mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MxcAvatar(
          client: client,
          avatarUrl: null,
          fallbackText: '  ',
          toneSeed: '@maya:zuno.chat',
        ),
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('a failing avatar asks once, however often it repaints', (
    tester,
  ) async {
    mediaResponse = () => http.Response('', 404);
    final address = uniqueMxc();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              MxcAvatar(
                client: client,
                avatarUrl: address,
                fallbackText: 'maya',
                toneSeed: '@maya:zuno.chat',
              ),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(loadFailed(address), isTrue);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(mediaRequests, hasLength(1));
    expect(find.text('M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('once the picture is there, the initial is gone', (tester) async {
    final address = uniqueMxc();
    await tester.pumpWidget(host(address));
    await pumpUntil(tester, () => !shows('M'), reason: 'the avatar to show');

    expect(find.text('M'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  group('a room keeps one colour wherever it shows', () {
    late Room room;

    setUp(() => room = buildTestRoom(client));

    void invitedBy(String inviter, {bool direct = false}) {
      room.membership = Membership.invite;
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          senderId: inviter,
          stateKey: client.userID!,
          content: {'membership': 'invite', 'is_direct': direct},
        ),
      );
    }

    void named(String name) => room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        senderId: '@bob:example.org',
        stateKey: '',
        content: {'name': name},
      ),
    );

    test('a direct chat takes the colour of the person in it', () {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [room.id],
        },
      );

      expect(roomToneSeed(room), '@bob:example.org');
    });

    test('a group takes its own', () {
      named('Weekend hike');

      expect(roomToneSeed(room), room.id);
    });

    test('an invite to a direct chat takes the colour of who sent it', () {
      invitedBy('@bob:example.org', direct: true);

      expect(roomToneSeed(room), '@bob:example.org');
    });

    test('an invite to a named group takes the group colour', () {
      named('Weekend hike');
      invitedBy('@bob:example.org');

      expect(roomToneSeed(room), room.id);
    });
  });
}
