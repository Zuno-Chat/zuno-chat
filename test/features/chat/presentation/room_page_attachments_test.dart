import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/chat/presentation/image_caption_composer_page.dart';
import 'package:zuno/features/chat/presentation/media_caption_composer_page.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/chat/presentation/video_caption_composer_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_video_player.dart';
import '../../../helpers/platform_capabilities.dart';
import 'room_page_harness.dart';

class _FakeImagePicker extends ImagePickerPlatform {
  final calls = <String>[];
  List<XFile> answer = [];
  Object? error;

  Future<T> _answer<T>(String call, T value) async {
    calls.add(call);
    final error = this.error;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) => _answer('image:${source.name}', answer.firstOrNull);

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) =>
      _answer('media', answer);

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) => _answer('video:${source.name}', answer.firstOrNull);
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.file('/picked/$name');

  @override
  XFile get xFile => XFile.fromData(bytes, path: '/picked/$name');

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _FakeFilePicker extends FilePickerPlatform {
  List<PlatformFile> answer = [];
  Object? error;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final error = this.error;
    if (error != null) throw error;
    return answer;
  }
}

class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 52.37,
    longitude: 4.89,
    timestamp: DateTime(2026, 9, 27),
    accuracy: 12,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

XFile _photo(String name) => XFile.fromData(
  img.encodeJpg(img.Image(width: 64, height: 48)),
  path: '/picked/$name',
  mimeType: 'image/jpeg',
);

XFile _video(String name) =>
    XFile('/picked/$name', name: name, mimeType: 'video/mp4');

void main() {
  late RoomPageHarness harness;
  late _FakeImagePicker picker;
  late _FakeFilePicker files;
  late Directory temp;
  late bool uploadsFail;
  late int? uploadLimit;
  late bool locationFails;

  setUp(() {
    picker = _FakeImagePicker();
    files = _FakeFilePicker();
    uploadsFail = false;
    uploadLimit = null;
    locationFails = false;
    final originalPicker = ImagePickerPlatform.instance;
    final originalFiles = FilePickerPlatform.instance;
    final originalGeolocator = GeolocatorPlatform.instance;
    ImagePickerPlatform.instance = picker;
    FilePickerPlatform.instance = files;
    GeolocatorPlatform.instance = _FakeGeolocator();
    installFakeVideoPlayer();
    temp = Directory.systemTemp.createTempSync('zuno_room_send_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const video = MethodChannel('zuno/video');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(video, (call) async {
      final args = call.arguments as Map;
      switch (call.method) {
        case 'probe':
          return {
            'width': 480,
            'height': 270,
            'durationMs': 5000,
            'bitrate': 400000,
            'videoCodec': 'video/avc',
            'audioCodec': 'audio/mp4a-latm',
          };
        case 'remux':
          File(args['output'] as String).writeAsBytesSync([0, 0, 0, 24]);
          return true;
        case 'thumbnail':
          return {
            'bytes': Uint8List.fromList(
              img.encodeJpg(img.Image(width: 48, height: 27)),
            ),
            'width': 48,
            'height': 27,
            'mimeType': 'image/jpeg',
          };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(pathProvider, (call) async => temp.path);
    addTearDown(() {
      ImagePickerPlatform.instance = originalPicker;
      FilePickerPlatform.instance = originalFiles;
      GeolocatorPlatform.instance = originalGeolocator;
      messenger.setMockMethodCallHandler(video, null);
      messenger.setMockMethodCallHandler(pathProvider, null);
      temp.deleteSync(recursive: true);
    });
  });

  Future<void> openRoom(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    ambientCapabilities = capabilitiesLike(
      iosCapabilities,
      nativeVideoTools: true,
      nativeImageResize: false,
    );
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      capabilities: capabilitiesLike(iosCapabilities, nativeImageResize: false),
      overrides: overrides,
    );
    harness.respond = (request) {
      final path = request.url.path;
      if (path.endsWith('/media/config') && uploadLimit != null) {
        return http.Response(jsonEncode({'m.upload.size': uploadLimit}), 200);
      }
      if (path.contains('/upload')) {
        return uploadsFail
            ? http.Response(
                jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'boom'}),
                500,
              )
            : http.Response(
                jsonEncode({'content_uri': 'mxc://example.org/uploaded'}),
                200,
              );
      }
      if (locationFails && path.contains('/send/m.room.message/')) {
        return http.Response(
          jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
          403,
        );
      }
      return null;
    };
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
  }

  Future<void> choose(WidgetTester tester, String option) async {
    await tester.tap(find.byIcon(Icons.attach_file_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(option));
    await harness.drive(tester, turns: 4);
  }

  Future<void> sendFromComposer(WidgetTester tester, {String? tooltip}) async {
    await tester.tap(find.byTooltip(tooltip ?? 'Send'));
    await harness.drive(tester);
  }

  Map<String, Object?>? galleryOf(Map<String, Object?> content) =>
      content[galleryGroupKey] as Map<String, Object?>?;

  group('photos', () {
    testWidgets('a camera photo is captioned and sent', (tester) async {
      picker.answer = [_photo('IMG_1.jpg')];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      expect(picker.calls, ['image:camera']);
      expect(find.byType(ImageCaptionComposerPage), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'at the lake');
      await sendFromComposer(tester);

      final sent = harness.sent.single;
      expect(sent['msgtype'], 'm.image');
      expect(sent['body'], 'at the lake');
      expect(sent['url'], 'mxc://example.org/uploaded');
      expect(galleryOf(sent), isNull);
    });

    testWidgets('an abandoned camera sends nothing', (tester) async {
      await openRoom(tester);

      await choose(tester, 'Take photo');

      expect(find.byType(ImageCaptionComposerPage), findsNothing);
      expect(harness.sent, isEmpty);
    });

    testWidgets('leaving the caption screen sends nothing', (tester) async {
      picker.answer = [_photo('IMG_1.jpg')];
      await openRoom(tester);
      await choose(tester, 'Take photo');

      await tester.pageBack();
      await harness.drive(tester);

      expect(harness.sent, isEmpty);
    });

    testWidgets('several gallery photos go out as one gallery, in order', (
      tester,
    ) async {
      picker.answer = [_photo('a.jpg'), _photo('b.jpg')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      expect(picker.calls, ['media']);
      expect(find.text('1 of 2'), findsOneWidget);
      await sendFromComposer(tester, tooltip: 'Send all');
      await harness.drive(tester);

      expect(harness.sent, hasLength(2));
      final first = galleryOf(harness.sent[0])!;
      final second = galleryOf(harness.sent[1])!;
      expect((first['index'], first['count']), (0, 2));
      expect((second['index'], second['count']), (1, 2));
      expect(first['id'], second['id']);
    });

    testWidgets('a photo that cannot be read says so', (tester) async {
      picker.answer = [
        XFile.fromData(
          Uint8List(64),
          path: '/picked/broken.jpg',
          mimeType: 'image/jpeg',
        ),
      ];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await sendFromComposer(tester);
      expect(tester.takeException(), isA<Exception>());

      expect(harness.sent, isEmpty);
      expect(find.text('Cannot send this photo'), findsOneWidget);
    });

    testWidgets('a photo over the upload limit says what the limit is', (
      tester,
    ) async {
      uploadLimit = 1024 * 1024;
      final noise = img.Image(width: 900, height: 900);
      var seed = 7;
      for (final pixel in noise) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        pixel.setRgb(seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
      }
      picker.answer = [
        XFile.fromData(
          img.encodeJpg(noise, quality: 100),
          path: '/picked/huge.jpg',
          mimeType: 'image/jpeg',
        ),
      ];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      await sendFromComposer(tester);
      await harness.drive(tester, turns: 20);

      expect(harness.sent, isEmpty);
      expect(
        find.text('Too large to send. The limit is 1 MB.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed photo in a gallery can be retried from the chat', (
      tester,
    ) async {
      uploadsFail = true;
      picker.answer = [_photo('a.jpg'), _photo('b.jpg')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      await sendFromComposer(tester, tooltip: 'Send all');
      await harness.drive(tester);

      expect(harness.sent, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Not sent. Tap an item to try again.'), findsOneWidget);

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail).first);
      await harness.drive(tester);

      expect(harness.sent, hasLength(1));
      expect(galleryOf(harness.sent.single)!['index'], 0);
    });

    testWidgets('a photo that fails after leaving the chat still says so', (
      tester,
    ) async {
      final upload = Completer<void>();
      picker.answer = [_photo('IMG_1.jpg')];
      await openRoom(tester);
      final respond = harness.respond!;
      harness.respond = (request) async {
        if (!request.url.path.contains('/upload')) return respond(request);
        await upload.future;
        return http.Response(
          jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'boom'}),
          500,
        );
      };

      await choose(tester, 'Take photo');
      await sendFromComposer(tester);
      await tester.pumpWidget(
        await harness.app(home: const Scaffold(body: SizedBox())),
      );
      upload.complete();
      await harness.drive(tester);

      expect(find.byType(RoomPage), findsNothing);
      expect(find.text('Not sent. Try again.'), findsOneWidget);
    });

    testWidgets('a single failed photo goes again when its tile is tapped', (
      tester,
    ) async {
      uploadsFail = true;
      picker.answer = [_photo('IMG_1.jpg')];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      await sendFromComposer(tester);
      expect(harness.sent, isEmpty);

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail));
      await harness.drive(tester);

      expect(harness.sent.single['msgtype'], 'm.image');
      expect(find.text('Not sent. Tap to try again.'), findsNothing);
    });

    testWidgets('a single failed photo says so and goes again once back '
        'online', (tester) async {
      final status = StreamController<ConnectionStatus>.broadcast();
      addTearDown(status.close);
      uploadsFail = true;
      picker.answer = [_photo('IMG_1.jpg')];
      await openRoom(
        tester,
        overrides: [
          connectionStatusProvider.overrideWith((ref) => status.stream),
        ],
      );
      status.add(ConnectionStatus.online);
      await harness.drive(tester, turns: 2);

      await choose(tester, 'Take photo');
      await sendFromComposer(tester);

      expect(harness.sent, isEmpty);
      expect(find.text('Not sent. Tap to try again.'), findsOneWidget);
      expect(find.text('Not sent. Try again.'), findsNothing);

      uploadsFail = false;
      status.add(ConnectionStatus.noInternet);
      await harness.drive(tester, turns: 2);
      expect(harness.sent, isEmpty);
      status.add(ConnectionStatus.online);
      await harness.drive(tester);

      expect(harness.sent.single['msgtype'], 'm.image');
    });
  });

  group('when the picker fails', () {
    for (final (option, code, message) in [
      (
        'Take photo',
        'camera_access_denied',
        'Allow camera access to take photos and videos',
      ),
      ('Take photo', 'no_available_camera', 'Camera did not open. Try again.'),
      (
        'Record video',
        'camera_access_denied',
        'Allow camera access to take photos and videos',
      ),
      (
        'Choose from gallery',
        'photo_access_denied',
        'Allow photo access to send photos and videos',
      ),
      (
        'Choose from gallery',
        'multiple_request',
        'Photos did not open. Try again.',
      ),
    ]) {
      testWidgets('$option with $code says so', (tester) async {
        picker.error = PlatformException(code: code);
        await openRoom(tester);

        await choose(tester, option);

        expect(tester.takeException(), isNull);
        expect(find.text(message), findsOneWidget);
      });
    }

    testWidgets('a file picker that fails says so', (tester) async {
      files.error = PlatformException(code: 'unknown_path');
      await openRoom(tester);

      await choose(tester, 'Choose file');

      expect(tester.takeException(), isNull);
      expect(find.text('Files did not open. Try again.'), findsOneWidget);
    });
  });

  group('videos', () {
    testWidgets('a gallery video is captioned and sent with its size', (
      tester,
    ) async {
      picker.answer = [_video('clip.mp4')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      expect(find.byType(VideoCaptionComposerPage), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'waves');
      await sendFromComposer(tester);
      await harness.drive(tester);

      final sent = harness.sent.single;
      expect(sent['msgtype'], 'm.video');
      expect(sent['body'], 'waves');
      final info = sent['info']! as Map<String, Object?>;
      expect((info['w'], info['h'], info['duration']), (480, 270, 5000));
      expect(info['thumbnail_url'], 'mxc://example.org/uploaded');
    });

    testWidgets('a recorded video goes the same way', (tester) async {
      picker.answer = [_video('rec.mp4')];
      await openRoom(tester);

      await choose(tester, 'Record video');
      expect(picker.calls, ['video:camera']);
      await sendFromComposer(tester);
      await harness.drive(tester);

      expect(harness.sent.single['msgtype'], 'm.video');
    });

    testWidgets('an abandoned recording sends nothing', (tester) async {
      await openRoom(tester);

      await choose(tester, 'Record video');

      expect(find.byType(VideoCaptionComposerPage), findsNothing);
      expect(harness.sent, isEmpty);
    });

    testWidgets('a photo and a video share one caption screen and one '
        'gallery', (tester) async {
      picker.answer = [_photo('a.jpg'), _video('b.mp4')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      expect(find.byType(MediaCaptionComposerPage), findsOneWidget);
      await sendFromComposer(tester, tooltip: 'Send all');
      await harness.drive(tester);

      expect(
        [for (final s in harness.sent) s['msgtype']],
        ['m.image', 'm.video'],
      );
      expect([for (final s in harness.sent) galleryOf(s)!['index']], [0, 1]);
    });

    testWidgets('a failed video in a gallery can be retried from the chat', (
      tester,
    ) async {
      uploadsFail = true;
      picker.answer = [_photo('a.jpg'), _video('b.mp4')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      await sendFromComposer(tester, tooltip: 'Send all');
      await harness.drive(tester);
      expect(find.byType(GalleryFailedThumbnail), findsNWidgets(2));

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail).last);
      await harness.drive(tester);
      await harness.drive(tester);

      expect(harness.sent.single['msgtype'], 'm.video');
      expect(galleryOf(harness.sent.single)!['index'], 1);
    });

    testWidgets('two videos also share one caption screen', (tester) async {
      picker.answer = [_video('a.mp4'), _video('b.mp4')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');

      expect(find.byType(MediaCaptionComposerPage), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
    });
  });

  group('files', () {
    testWidgets('a file is sent under its name', (tester) async {
      files.answer = [
        _PickedFile('notes.pdf', Uint8List.fromList([1, 2])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await harness.drive(tester);

      expect(harness.sent.single['msgtype'], 'm.file');
      expect(harness.sent.single['body'], 'notes.pdf');
    });

    testWidgets('every picked file is sent, not just one', (tester) async {
      files.answer = [
        _PickedFile('a.pdf', Uint8List.fromList([1])),
        _PickedFile('b.txt', Uint8List.fromList([2])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await harness.drive(tester);

      expect([for (final s in harness.sent) s['body']], ['a.pdf', 'b.txt']);
    });

    testWidgets('nothing picked sends nothing', (tester) async {
      await openRoom(tester);

      await choose(tester, 'Choose file');

      expect(harness.sent, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed upload says so', (tester) async {
      uploadsFail = true;
      files.answer = [
        _PickedFile('a.pdf', Uint8List.fromList([1])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await harness.drive(tester);

      expect(find.text('Not sent. Try again.'), findsOneWidget);
      expect(find.text('Not sent · Tap to retry'), findsNothing);
    });
  });

  group('location', () {
    Future<void> shareLocation(WidgetTester tester) async {
      await choose(tester, 'Location');
      await harness.drive(tester, turns: 4);
      await tester.tap(find.text('Send location'));
      await harness.drive(tester);
    }

    Future<void> openRoomForLocation(WidgetTester tester) => openRoom(
      tester,
      overrides: [mapTilesProvider.overrideWith((ref) async => null)],
    );

    testWidgets('the found location is sent', (tester) async {
      await openRoomForLocation(tester);

      await shareLocation(tester);

      expect(harness.sent.single['msgtype'], 'm.location');
      expect(harness.sent.single['geo_uri'], startsWith('geo:52.37,4.89'));
    });

    testWidgets('a refused send says so', (tester) async {
      locationFails = true;
      await openRoomForLocation(tester);

      await shareLocation(tester);

      expect(find.text('Location not sent. Try again.'), findsOneWidget);
    });
  });

  testWidgets('an unsent message goes again once back online', (tester) async {
    final status = StreamController<ConnectionStatus>.broadcast();
    addTearDown(status.close);
    ambientCapabilities = iosCapabilities;
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      capabilities: iosCapabilities,
      overrides: [
        connectionStatusProvider.overrideWith((ref) => status.stream),
      ],
    );
    harness.db.events = [
      buildTestEvent(
        harness.room,
        eventId: 'txn-unsent',
        senderId: '@me:example.org',
        originServerTs: DateTime(2026, 9, 20, 12, 5),
        status: EventStatus.error,
        content: {'msgtype': 'm.text', 'body': 'still there?'},
      ),
      harness.message(r'$m1'),
    ];
    await harness.pumpRoomPage(tester);
    status.add(ConnectionStatus.noInternet);
    await harness.drive(tester, turns: 2);
    expect(harness.sent, isEmpty);

    status.add(ConnectionStatus.online);
    await harness.drive(tester);

    expect(harness.sent.single['body'], 'still there?');
  });
}
