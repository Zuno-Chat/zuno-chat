import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/upload_progress_http_client.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_audio_route.dart';
import 'package:zuno/features/calls/presentation/call_view.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import '../../test/helpers/fake_matrix.dart';

const _outDir = 'build/screenshots';
const _me = '@me:example.org';
final _shot = GlobalKey();

class ScreenshotDevice {
  final String name;
  final Size size;
  final double ratio;
  final TargetPlatform platform;

  const ScreenshotDevice(this.name, this.size, this.ratio, this.platform);

  AppPlatform get app =>
      platform == TargetPlatform.iOS ? AppPlatform.ios : AppPlatform.android;
}

const iphone69 = ScreenshotDevice(
  'iphone-6.9in',
  Size(440, 956),
  3,
  TargetPlatform.iOS,
);

const androidPhone = ScreenshotDevice(
  'android-phone',
  Size(360, 640),
  3,
  TargetPlatform.android,
);

const ipad13 = ScreenshotDevice(
  'ipad-13in',
  Size(1032, 1376),
  2,
  TargetPlatform.iOS,
);

const androidTablet10 = ScreenshotDevice(
  'android-tablet-10in',
  Size(800, 1280),
  2,
  TargetPlatform.android,
);

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final material = '$artifacts/material_fonts';
  await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await _loadFont('Roboto', [
    for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black'])
      '$material/Roboto-$weight.ttf',
  ]);
  for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
    await _loadFont(family, ['/System/Library/Fonts/SFNS.ttf']);
  }
}

void _mockChannels() {
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channels = [
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    const MethodChannel('zuno/calls'),
    const MethodChannel('com.llfbandit.record/messages'),
  ];
  for (final channel in channels) {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'initialize' ? true : null,
    );
  }
  const prefs = MethodChannel('plugins.flutter.io/shared_preferences');
  messenger.setMockMethodCallHandler(
    prefs,
    (call) async => call.method == 'getAll' ? <String, Object>{} : true,
  );
  const network = EventChannel('zuno/network');
  messenger.setMockStreamHandler(
    network,
    MockStreamHandler.inline(onListen: (_, _) {}),
  );
  addTearDown(() {
    for (final channel in [...channels, prefs]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(network, null);
  });
}

class _ShotDatabase extends StoredEventsFakeDatabaseApi {
  @override
  int get maxFileSize => 0;

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> content,
  ) async {}
}

class _ShotClient extends Client {
  _ShotClient({required super.database, required super.httpClient})
    : super('screenshots');

  @override
  bool get encryptionEnabled => true;
}

class _World {
  final db = _ShotDatabase();
  final httpClient = UploadProgressHttpClient(
    MockClient(
      (request) async => http.Response(
        request.url.path.endsWith('/versions')
            ? '{"versions":["v1.11"]}'
            : '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
  late final Client client;
  final directChats = <String, List<String>>{};
  final now = DateUtils.dateOnly(DateTime.now())
      .add(const Duration(hours: 9, minutes: 41));

  _World() {
    client = _ShotClient(database: db, httpClient: httpClient);
    client.setUserId(_me);
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'token';
  }

  Room room(
    String id, {
    String? name,
    required Map<String, String> members,
    int unread = 0,
    bool direct = false,
  }) {
    final room = Room(
      id: id,
      client: client,
      notificationCount: unread,
      highlightCount: 0,
    )..partial = false;
    room.setState(
      StrippedStateEvent(
        type: EventTypes.Encryption,
        senderId: _me,
        stateKey: '',
        content: {'algorithm': 'm.megolm.v1.aes-sha2'},
      ),
    );
    if (name != null) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: _me,
          stateKey: '',
          content: {'name': name},
        ),
      );
    }
    for (final entry in {_me: 'Alex', ...members}.entries) {
      room.setState(
        User(
          entry.key,
          membership: 'join',
          displayName: entry.value,
          room: room,
        ),
      );
    }
    room.summary.mJoinedMemberCount = members.length + 1;
    room.summary.mHeroes = members.keys.toList();
    if (direct) directChats[members.keys.single] = [id];
    client.rooms.add(room);
    return room;
  }

  Event message(
    Room room,
    String id,
    String sender,
    Map<String, Object?> content, {
    required Duration ago,
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: sender,
    originServerTs: now.subtract(ago),
    status: EventStatus.synced,
    content: content,
  );

  Event text(
    Room room,
    String id,
    String sender,
    String body, {
    required Duration ago,
    String? replyTo,
  }) => message(room, id, sender, {
    'msgtype': 'm.text',
    'body': body,
    if (replyTo != null)
      'm.relates_to': {
        'm.in_reply_to': {'event_id': replyTo},
      },
  }, ago: ago);

  void finish() {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: directChats,
    );
  }
}

void _seedChatList(_World w) {
  void last(Room room, String sender, String body, Duration ago) =>
      room.lastEvent = w.text(
        room,
        '\$${room.id}-last',
        sender,
        body,
        ago: ago,
      );

  final maya = w.room(
    '!maya:example.org',
    members: {'@maya:example.org': 'Maya Chen'},
    unread: 2,
    direct: true,
  );
  last(
    maya,
    '@maya:example.org',
    'Landed. Call you after dinner?',
    const Duration(minutes: 2),
  );

  final hike = w.room(
    '!hike:example.org',
    name: 'Weekend hike',
    members: {
      '@priya:example.org': 'Priya',
      '@sam:example.org': 'Sam',
      '@lena:example.org': 'Lena',
    },
    unread: 4,
  );
  last(
    hike,
    '@lena:example.org',
    'Thank you, see you then',
    const Duration(minutes: 7),
  );

  final family = w.room(
    '!family:example.org',
    name: 'Family',
    members: {
      '@dad:example.org': 'Dad',
      '@mum:example.org': 'Mum',
      '@leo:example.org': 'Leo',
    },
    unread: 1,
  );
  last(
    family,
    '@mum:example.org',
    'Dinner at ours on Sunday, 6 pm',
    const Duration(minutes: 34),
  );

  final jonas = w.room(
    '!jonas:example.org',
    members: {'@jonas:example.org': 'Jonas Weber'},
    direct: true,
  );
  last(
    jonas,
    _me,
    'Sounds good, see you at 8',
    const Duration(hours: 1, minutes: 12),
  );

  final books = w.room(
    '!books:example.org',
    name: 'Book club',
    members: {
      '@ines:example.org': 'Ines',
      '@marco:example.org': 'Marco',
      '@ruth:example.org': 'Ruth',
    },
  );
  last(
    books,
    '@ines:example.org',
    'Chapters 9 and 10 for Thursday',
    const Duration(hours: 1, minutes: 40),
  );

  final lena = w.room(
    '!lena:example.org',
    members: {'@lena:example.org': 'Lena Okafor'},
    direct: true,
  );
  lena.lastEvent = w.message(lena, r'$lena-voice', '@lena:example.org', {
    'msgtype': 'm.audio',
    'body': 'Voice message',
    'url': 'mxc://example.org/voice',
    'info': {'duration': 14000, 'mimetype': 'audio/ogg'},
    'org.matrix.msc3245.voice': <String, Object?>{},
  }, ago: const Duration(hours: 2, minutes: 10));

  final flat = w.room(
    '!flat:example.org',
    name: 'Flat 4B',
    members: {'@kai:example.org': 'Kai', '@zoe:example.org': 'Zoe'},
  );
  last(
    flat,
    '@kai:example.org',
    'Rent is in. Whose turn is it for the bins?',
    const Duration(hours: 15),
  );

  final rosa = w.room(
    '!rosa:example.org',
    members: {'@rosa:example.org': 'Grandma Rosa'},
    direct: true,
  );
  last(
    rosa,
    '@rosa:example.org',
    'Thank you for the flowers, they are lovely',
    const Duration(days: 1, hours: 2),
  );

  final climb = w.room(
    '!climb:example.org',
    name: 'Climbing',
    members: {'@omar:example.org': 'Omar', '@jess:example.org': 'Jess'},
  );
  last(
    climb,
    '@omar:example.org',
    'The wall is open until 10 tonight',
    const Duration(days: 1, hours: 5),
  );

  final tom = w.room(
    '!tom:example.org',
    members: {'@tom:example.org': 'Tom Alvarez'},
    direct: true,
  );
  tom.lastEvent = w.message(tom, r'$tom-photo', '@tom:example.org', {
    'msgtype': 'm.image',
    'body': 'IMG_2041.jpg',
    'url': 'mxc://example.org/photo',
    'info': {'w': 1200, 'h': 900, 'mimetype': 'image/jpeg'},
  }, ago: const Duration(days: 2));

  final garden = w.room(
    '!garden:example.org',
    name: 'Community garden',
    members: {
      '@hana:example.org': 'Hana',
      '@eli:example.org': 'Eli',
      '@ade:example.org': 'Ade',
    },
  );
  last(
    garden,
    '@hana:example.org',
    'Tomatoes are ready to pick',
    const Duration(days: 3),
  );

  final ana = w.room(
    '!ana:example.org',
    members: {'@ana:example.org': 'Ana Ribeiro'},
    direct: true,
  );
  last(ana, _me, 'Happy birthday. Have a great day', const Duration(days: 4));

  final noah = w.room(
    '!noah:example.org',
    members: {'@noah:example.org': 'Noah Kim'},
    direct: true,
  );
  last(
    noah,
    '@noah:example.org',
    'Did you get the tickets?',
    const Duration(days: 5),
  );

  final run = w.room(
    '!run:example.org',
    name: 'Sunday run',
    members: {'@ben:example.org': 'Ben', '@cleo:example.org': 'Cleo'},
  );
  last(
    run,
    '@ben:example.org',
    '10 km, easy pace, meet at the park gate',
    const Duration(days: 6),
  );

  final mia = w.room(
    '!mia:example.org',
    members: {'@mia:example.org': 'Mia Novak'},
    direct: true,
  );
  last(
    mia,
    '@mia:example.org',
    'Can you send me that soup recipe?',
    const Duration(days: 7),
  );

  final choir = w.room(
    '!choir:example.org',
    name: 'Choir',
    members: {'@ida:example.org': 'Ida', '@raf:example.org': 'Raf'},
  );
  last(
    choir,
    '@ida:example.org',
    'Rehearsal moves to Wednesday this week',
    const Duration(days: 8),
  );

  final dev = w.room(
    '!dev:example.org',
    members: {'@dev:example.org': 'Dev Patel'},
    direct: true,
  );
  last(dev, _me, 'Thanks for the help with the move', const Duration(days: 9));
}

Room _seedRoom(_World w) {
  const priya = '@priya:example.org';
  const sam = '@sam:example.org';
  const lena = '@lena:example.org';
  final room = w.room(
    '!hike:example.org',
    name: 'Weekend hike',
    members: {priya: 'Priya', sam: 'Sam', lena: 'Lena'},
  );
  final lines = <(String, String, Duration, String?)>[
    (
      lena,
      'Found the photos from the ridge in June.',
      const Duration(hours: 17, minutes: 5),
      null,
    ),
    (priya, 'That view is still my favorite.', const Duration(hours: 17), null),
    (
      _me,
      'We should go back before it gets cold.',
      const Duration(hours: 16, minutes: 52),
      null,
    ),
    (
      sam,
      'Agreed. Let me check the weather.',
      const Duration(hours: 16, minutes: 48),
      null,
    ),
    (
      sam,
      'Who is up for a hike this weekend?',
      const Duration(hours: 15),
      null,
    ),
    (
      priya,
      'Me. I have wanted to do the lake loop for weeks.',
      const Duration(hours: 14, minutes: 56),
      null,
    ),
    (
      _me,
      'Same. Saturday or Sunday?',
      const Duration(hours: 14, minutes: 51),
      null,
    ),
    (
      sam,
      'Saturday looks dry. Sunday is meant to rain.',
      const Duration(hours: 14, minutes: 47),
      null,
    ),
    (priya, 'Saturday then.', const Duration(hours: 14, minutes: 46), null),
    (lena, 'Just saw this. Can I join?', const Duration(minutes: 52), null),
    (sam, 'Of course. Trailhead at 8.', const Duration(minutes: 49), null),
    (
      _me,
      '8 works. I will bring the big thermos.',
      const Duration(minutes: 47),
      null,
    ),
    (lena, 'How long is the loop?', const Duration(minutes: 31), null),
    (
      priya,
      'About 14 km, with one steep bit near the lake.',
      const Duration(minutes: 29),
      null,
    ),
    (
      priya,
      'There is a cafe at the top that opens at 11.',
      const Duration(minutes: 28),
      null,
    ),
    (_me, 'Perfect timing for a break.', const Duration(minutes: 24), null),
    (
      lena,
      'Can someone give me a lift? My car is in the shop.',
      const Duration(minutes: 12),
      null,
    ),
    (sam, 'I can pick you up at 7:30', const Duration(minutes: 9), r'$hike-16'),
    (lena, 'Thank you, see you then', const Duration(minutes: 7), null),
  ];
  final events = [
    for (final (i, (sender, body, ago, replyTo)) in lines.indexed)
      w.text(room, '\$hike-$i', sender, body, ago: ago, replyTo: replyTo),
  ];
  w.db.events = events.reversed.toList();
  room.lastEvent = events.last;
  room.ephemerals['m.typing'] = BasicEvent(
    type: 'm.typing',
    content: {
      'user_ids': [priya],
    },
  );
  return room;
}

Widget _voiceCall(_World w) {
  const maya = '@maya:example.org';
  final room = w.room(
    '!maya:example.org',
    members: {maya: 'Maya Chen'},
    direct: true,
  );
  CallViewParticipant person(String userId, {required bool local}) =>
      CallViewParticipant(
        participant: CallEngineParticipant(
          id: VoipParticipantId(userId: userId, deviceId: 'DEVICE'),
          isLocal: local,
          encrypted: true,
        ),
        renderer: null,
        user: local ? null : room.unsafeGetUserFromMemoryOrFallback(userId),
        encrypting: false,
      );
  return Theme(
    data: zunoDarkTheme,
    child: CallView(
      room: room,
      kind: CallKind.voice,
      connecting: false,
      calling: false,
      local: person(_me, local: true),
      remote: [person(maya, local: false)],
      talkingSince: DateTime.now().subtract(
        const Duration(minutes: 4, seconds: 12),
      ),
      reconnecting: false,
      quality: CallQuality.good,
      audioRoute: CallAudioRoute.earpiece,
      onToggleMute: () {},
      onToggleCamera: () {},
      onSwitchCamera: () {},
      onToggleSpeaker: () {},
      onHangUp: () {},
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  ScreenshotDevice device,
  String name,
) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: device.ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgb = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: data!.buffer,
      numChannels: 4,
    ).convert(numChannels: 3);
    File('$_outDir/${device.name}-$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(rgb));
  });
}

Future<void> _pump(
  WidgetTester tester,
  ScreenshotDevice device,
  _World w,
  Widget home,
  ThemeMode mode, {
  Widget? pushed,
}) async {
  _mockChannels();
  w.finish();
  tester.view.physicalSize = device.size * device.ratio;
  tester.view.devicePixelRatio = device.ratio;
  addTearDown(tester.view.reset);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      matrixClientProvider.overrideWithValue(w.client),
      uploadProgressHttpClientProvider.overrideWithValue(w.httpClient),
      sharedPreferencesProvider.overrideWithValue(prefs),
      platformCapabilitiesProvider.overrideWithValue(
        capabilitiesFor(device.app),
      ),
    ],
  );
  addTearDown(container.dispose);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: zunoLightTheme,
          darkTheme: zunoDarkTheme,
          themeMode: mode,
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          navigatorKey: navigator,
          home: home,
        ),
      ),
    ),
  );
  if (pushed != null) {
    await tester.pump();
    unawaited(
      navigator.currentState!.push(MaterialPageRoute(builder: (_) => pushed)),
    );
  }
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump(const Duration(seconds: 2));
}

void screenshotTests(ScreenshotDevice device) {
  setUpAll(_loadFonts);
  final variant = TargetPlatformVariant.only(device.platform);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('${device.name} chat list $suffix', variant: variant, (
      tester,
    ) async {
      final w = _World();
      _seedChatList(w);
      await _pump(tester, device, w, const RoomListPage(), mode);
      await _capture(tester, device, 'chat-list-$suffix');
    });

    testWidgets('${device.name} room $suffix', variant: variant, (
      tester,
    ) async {
      final w = _World();
      final room = _seedRoom(w);
      await _pump(
        tester,
        device,
        w,
        const Scaffold(),
        mode,
        pushed: RoomPage(room: room),
      );
      await _capture(tester, device, 'room-$suffix');
    });
  }

  testWidgets('${device.name} voice call', variant: variant, (tester) async {
    final w = _World();
    await _pump(tester, device, w, _voiceCall(w), ThemeMode.dark);
    await _capture(tester, device, 'voice-call');
  });

  tearDownAll(() {
    if (kDebugMode) debugPrint('Screenshots written to $_outDir');
  });
}
