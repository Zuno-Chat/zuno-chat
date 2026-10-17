import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/upload_http_client.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/features/chat/data/discarded_sends.dart';
import 'package:zuno/features/chat/presentation/caption_bar.dart';
import 'package:zuno/features/chat/presentation/image_caption_composer_page.dart';
import 'package:zuno/features/chat/presentation/media_caption_composer_page.dart';
import 'package:zuno/features/chat/presentation/message_composer.dart';
import 'package:zuno/features/chat/presentation/message_contents/file_message.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/not_sent.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/chat/presentation/video_caption_composer_page.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_geolocator.dart';
import '../../../helpers/fake_live_location.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_video_player.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/pump_until.dart';
import '../../../helpers/route_launcher.dart';
import 'room_page_harness.dart';

XFile _video(String name) =>
    XFile('/picked/$name', name: name, mimeType: 'video/mp4');

class _CachedFilesDatabase extends SendingFakeDatabaseApi {
  @override
  Future<Uint8List?> getFile(Uri mxcUri) async => Uint8List.fromList([1, 2, 3]);
}

class _StoringDatabase extends SendingFakeDatabaseApi {
  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {
    if (event is! MatrixEvent) return;
    final stored = Event.fromMatrixEvent(event, client.getRoomById(roomId)!);
    final txid = stored.transactionId;
    events.removeWhere(
      (e) =>
          e.eventId == stored.eventId ||
          (txid != null && e.transactionId == txid),
    );
    events.insert(0, stored);
  }
}

void main() {
  late RoomPageHarness harness;
  late FakeImagePicker picker;
  late FakeFilePicker files;
  late Directory temp;
  late bool uploadsFail;
  late int? uploadLimit;
  late bool locationFails;
  late bool sendsGiveUpAtOnce;
  late Future<void> Function(String method) beforeVideoTool;

  setUp(() {
    sendsGiveUpAtOnce = false;
    beforeVideoTool = (_) async {};
    picker = installFakeImagePicker();
    files = installFakeFilePicker();
    uploadsFail = false;
    uploadLimit = null;
    locationFails = false;
    final originalGeolocator = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = FakeGeolocator()
      ..position = fakePosition(latitude: 52.37, longitude: 4.89, accuracy: 12);
    installFakeVideoPlayer();
    temp = Directory.systemTemp.createTempSync('zuno_room_send_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const video = MethodChannel('zuno/video');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(video, (call) async {
      await beforeVideoTool(call.method);
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
      GeolocatorPlatform.instance = originalGeolocator;
      messenger.setMockMethodCallHandler(video, null);
      messenger.setMockMethodCallHandler(pathProvider, null);
      temp.deleteSync(recursive: true);
    });
  });

  File pickerCopy(String name, List<int> bytes) =>
      File('${temp.path}/picker-$name/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  XFile photo(String name, {List<int>? bytes}) {
    final copy = pickerCopy(
      name,
      bytes ?? img.encodeJpg(img.Image(width: 64, height: 48)),
    );
    return XFile(copy.path, mimeType: 'image/jpeg');
  }

  bool pickerCopyLeft(XFile picked) =>
      File(picked.path).existsSync() || File(picked.path).parent.existsSync();

  Uint8List tooLargePhoto() {
    final noise = img.Image(width: 900, height: 900);
    var seed = 7;
    for (final pixel in noise) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      pixel.setRgb(seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
    }
    return img.encodeJpg(noise, quality: 100);
  }

  Future<void> openRoom(
    WidgetTester tester, {
    List<Override> overrides = const [],
    bool encrypting = false,
    bool reopenable = false,
    SendingFakeDatabaseApi? db,
    Map<String, Object> preferences = const {},
    void Function(Room room)? prepare,
  }) async {
    ambientCapabilities = capabilitiesLike(
      iosCapabilities,
      nativeVideoTools: true,
      nativeImageResize: false,
    );
    harness = RoomPageHarness(
      db: db ?? (reopenable ? _StoringDatabase() : SendingFakeDatabaseApi()),
      capabilities: capabilitiesLike(iosCapabilities, nativeImageResize: false),
      overrides: overrides,
      encrypting: encrypting,
      sendsGiveUpAtOnce: sendsGiveUpAtOnce,
      preferences: preferences,
    );
    harness.db.events = [harness.message(r'$m1')];
    prepare?.call(harness.room);
    harness.respond = (request) {
      final path = request.url.path;
      if (path.endsWith('/media/config') && uploadLimit != null) {
        return http.Response(jsonEncode({'m.upload.size': uploadLimit}), 200);
      }
      if (path.contains('/download/') || path.contains('/thumbnail/')) {
        return http.Response.bytes(
          img.encodeJpg(img.Image(width: 48, height: 27)),
          200,
          headers: {'content-type': 'image/jpeg'},
        );
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
    if (!reopenable) {
      await harness.pumpRoomPage(tester);
      return;
    }
    await tester.pumpWidget(
      await harness.app(
        home: Scaffold(
          body: routeLauncher((_) => RoomPage(room: harness.room)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await harness.settle(tester);
  }

  Future<void> openAttachMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.attach_file_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> choose(WidgetTester tester, String option) async {
    await openAttachMenu(tester);
    await tester.tap(find.text(option));
    await harness.drive(tester, turns: 4);
  }

  int failedTiles() => find.byType(GalleryFailedThumbnail).evaluate().length;

  Future<void> sendFromComposer(
    WidgetTester tester, {
    String tooltip = 'Send',
    required String awaiting,
    required bool Function() until,
  }) async {
    await tester.tap(find.byTooltip(tooltip));
    await pumpUntil(
      tester,
      () => find.byType(CaptionBar).evaluate().isEmpty,
      reason: 'the caption screen to close',
    );
    await pumpUntil(tester, until, reason: awaiting);
  }

  Map<String, Object?>? galleryOf(Map<String, Object?> content) =>
      content[galleryGroupKey] as Map<String, Object?>?;

  group('photos', () {
    testWidgets('the floating call window keeps clear of the attachments '
        'sheet', (tester) async {
      await openRoom(tester);

      await openAttachMenu(tester);

      expect(
        find.ancestor(
          of: find.text('Take photo'),
          matching: find.byType(KeepClearArea),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a camera photo is captioned and sent', (tester) async {
      picker.answer = [photo('IMG_1.jpg')];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      expect(picker.calls, ['image:camera']);
      expect(find.byType(ImageCaptionComposerPage), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'at the lake');
      await sendFromComposer(
        tester,
        awaiting: 'the photo to be sent',
        until: () => harness.sent.isNotEmpty,
      );

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
      picker.answer = [photo('IMG_1.jpg')];
      await openRoom(tester);
      await choose(tester, 'Take photo');

      await tester.pageBack();
      await harness.drive(tester);

      expect(harness.sent, isEmpty);
    });

    testWidgets('several gallery photos go out as one gallery, in order', (
      tester,
    ) async {
      picker.answer = [photo('a.jpg'), photo('b.jpg')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      expect(picker.calls, ['media']);
      expect(find.text('1 of 2'), findsOneWidget);
      await sendFromComposer(
        tester,
        tooltip: 'Send all',
        awaiting: 'both photos to be sent',
        until: () => harness.sent.length == 2,
      );

      expect(harness.sent, hasLength(2));
      final first = galleryOf(harness.sent[0])!;
      final second = galleryOf(harness.sent[1])!;
      expect((first['index'], first['count']), (0, 2));
      expect((second['index'], second['count']), (1, 2));
      expect(first['id'], second['id']);
    });

    testWidgets('a photo that cannot be read says so', (tester) async {
      picker.answer = [photo('broken.jpg', bytes: Uint8List(64))];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty,
        reason: 'the preview to show the photo cannot be read',
      );
      await sendFromComposer(
        tester,
        awaiting: 'the photo to be refused',
        until: () => shows('Cannot send this photo'),
      );

      expect(harness.sent, isEmpty);
      expect(find.text('Cannot send this photo'), findsOneWidget);
    });

    testWidgets('a photo over the upload limit says what the limit is', (
      tester,
    ) async {
      uploadLimit = 1024 * 1024;
      picker.answer = [photo('huge.jpg', bytes: tooLargePhoto())];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the upload limit to be named',
        until: () => shows('Too large to send. The limit is 1 MB.'),
      );

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
      picker.answer = [photo('a.jpg'), photo('b.jpg')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      await sendFromComposer(
        tester,
        tooltip: 'Send all',
        awaiting: 'both photos to fail',
        until: () => shows('Not sent. Tap an item to try again.'),
      );

      expect(harness.sent, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Not sent. Tap an item to try again.'), findsOneWidget);

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail).first);
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the retried photo to be sent',
      );

      expect(harness.sent, hasLength(1));
      expect(galleryOf(harness.sent.single)!['index'], 0);
    });

    testWidgets('a photo that fails after leaving the chat says so, and waits '
        'in the chat to go again', (tester) async {
      final upload = Completer<void>();
      uploadsFail = true;
      picker.answer = [photo('IMG_1.jpg')];
      await openRoom(tester, reopenable: true);
      final respond = harness.respond!;
      harness.respond = (request) async {
        if (request.url.path.contains('/upload')) await upload.future;
        return respond(request);
      };

      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the upload to start',
        until: () =>
            harness.httpRequests.any((r) => r.url.path.contains('/upload')),
      );
      await tester.pageBack();
      await harness.settle(tester);
      upload.complete();
      await pumpUntil(
        tester,
        () => shows('Not sent. Try again.'),
        reason: 'the failure to be reported',
      );
      expect(find.byType(RoomPage), findsNothing);

      uploadsFail = false;
      await tester.tap(find.text('open'));
      await harness.settle(tester);
      await tester.tap(find.byType(GalleryFailedThumbnail));
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the photo to go again',
      );

      expect(harness.sent.single['msgtype'], 'm.image');
    });

    group('when you leave the chat mid-way', () {
      Future<void> sendThenLeave(
        WidgetTester tester, {
        required String option,
        String? tooltip,
      }) async {
        final firstUpload = Completer<void>();
        final respond = harness.respond!;
        var uploads = 0;
        harness.respond = (request) async {
          if (request.url.path.contains('/upload') && uploads++ == 0) {
            await firstUpload.future;
          }
          return respond(request);
        };
        await choose(tester, option);
        bool uploading() =>
            harness.httpRequests.any((r) => r.url.path.contains('/upload'));
        if (tooltip == null) {
          await pumpUntil(tester, uploading, reason: 'the first upload');
        } else {
          await sendFromComposer(
            tester,
            tooltip: tooltip,
            awaiting: 'the first upload',
            until: uploading,
          );
        }
        await tester.pumpWidget(
          await harness.app(home: const Scaffold(body: SizedBox())),
        );
        firstUpload.complete();
      }

      testWidgets('every photo still goes', (tester) async {
        picker.answer = [photo('a.jpg'), photo('b.jpg'), photo('c.jpg')];
        await openRoom(tester);

        await sendThenLeave(
          tester,
          option: 'Choose from gallery',
          tooltip: 'Send all',
        );
        await pumpUntil(
          tester,
          () => harness.sent.length == 3,
          reason: 'every photo to be sent',
        );

        expect(find.byType(RoomPage), findsNothing);
        expect(
          [for (final s in harness.sent) galleryOf(s)!['index']],
          [0, 1, 2],
        );
      });

      testWidgets('a photo that cannot be sent still says so', (tester) async {
        picker.answer = [
          photo('a.jpg'),
          photo('broken.jpg', bytes: Uint8List(64)),
        ];
        await openRoom(tester);

        await sendThenLeave(
          tester,
          option: 'Choose from gallery',
          tooltip: 'Send all',
        );
        await pumpUntil(
          tester,
          () => shows('Cannot send this photo'),
          reason: 'the refused photo to be named',
        );

        expect(harness.sent, hasLength(1));
      });

      testWidgets('a photo over the upload limit still says so', (
        tester,
      ) async {
        uploadLimit = 1024 * 1024;
        picker.answer = [
          photo('a.jpg'),
          photo('huge.jpg', bytes: tooLargePhoto()),
        ];
        await openRoom(tester);

        await sendThenLeave(
          tester,
          option: 'Choose from gallery',
          tooltip: 'Send all',
        );
        await pumpUntil(
          tester,
          () => shows('Too large to send. The limit is 1 MB.'),
          reason: 'the upload limit to be named',
        );

        expect(harness.sent, hasLength(1));
      });

      testWidgets('every picked file still goes', (tester) async {
        files.picked = [
          FakePickedFile('a.pdf', Uint8List.fromList([1])),
          FakePickedFile('b.pdf', Uint8List.fromList([2])),
        ];
        await openRoom(tester);

        await sendThenLeave(tester, option: 'Choose file');
        await pumpUntil(
          tester,
          () => harness.sent.length == 2,
          reason: 'both files to be sent',
        );

        expect([for (final s in harness.sent) s['body']], ['a.pdf', 'b.pdf']);
      });
    });

    group('picker copies', () {
      testWidgets('a sent photo leaves no copy behind', (tester) async {
        final picked = photo('IMG_1.jpg');
        picker.answer = [picked];
        await openRoom(tester);

        await choose(tester, 'Take photo');
        await sendFromComposer(
          tester,
          awaiting: 'the photo to be sent and its copy removed',
          until: () => harness.sent.isNotEmpty && !pickerCopyLeft(picked),
        );

        expect(pickerCopyLeft(picked), isFalse);
      });

      testWidgets('leaving the caption screen removes the copies', (
        tester,
      ) async {
        final picked = [photo('a.jpg'), photo('b.jpg')];
        picker.answer = picked;
        await openRoom(tester);
        await choose(tester, 'Choose from gallery');

        await tester.pageBack();
        await pumpUntil(
          tester,
          () => !picked.any(pickerCopyLeft),
          reason: 'the copies to be removed',
        );

        expect(harness.sent, isEmpty);
      });

      testWidgets('a failed photo keeps its copy until it goes again', (
        tester,
      ) async {
        uploadsFail = true;
        final picked = photo('IMG_1.jpg');
        picker.answer = [picked];
        await openRoom(tester);

        await choose(tester, 'Take photo');
        await sendFromComposer(
          tester,
          awaiting: 'the photo to fail',
          until: () => failedTiles() == 1,
        );
        await harness.drive(tester, turns: 2);
        expect(pickerCopyLeft(picked), isTrue);

        uploadsFail = false;
        await tester.tap(find.byType(GalleryFailedThumbnail));
        await pumpUntil(
          tester,
          () => harness.sent.isNotEmpty && !pickerCopyLeft(picked),
          reason: 'the photo to go again and its copy to be removed',
        );

        expect(harness.sent.single['msgtype'], 'm.image');
      });

      testWidgets('a failed photo keeps its copy after leaving the chat, and '
          'goes again from the chat opened again', (tester) async {
        uploadsFail = true;
        final picked = photo('IMG_1.jpg');
        picker.answer = [picked];
        await openRoom(tester, reopenable: true);

        await choose(tester, 'Take photo');
        await sendFromComposer(
          tester,
          awaiting: 'the photo to fail',
          until: () => failedTiles() == 1,
        );
        await tester.pageBack();
        await harness.settle(tester);
        expect(pickerCopyLeft(picked), isTrue);

        await tester.tap(find.text('open'));
        await harness.settle(tester);
        expect(failedTiles(), 1);

        uploadsFail = false;
        await tester.tap(find.byType(GalleryFailedThumbnail));
        await pumpUntil(
          tester,
          () => harness.sent.isNotEmpty && !pickerCopyLeft(picked),
          reason: 'the photo to go again and its copy to be removed',
        );

        expect(harness.sent.single['msgtype'], 'm.image');
      });

      testWidgets('a recorded video leaves no copy behind', (tester) async {
        final recorded = pickerCopy('rec.mp4', [0, 0, 0, 24]);
        picker.answer = [XFile(recorded.path, mimeType: 'video/mp4')];
        await openRoom(tester);

        await choose(tester, 'Record video');
        await sendFromComposer(
          tester,
          awaiting: 'the video to be sent and its copy removed',
          until: () => harness.sent.isNotEmpty && !recorded.existsSync(),
        );

        expect(recorded.parent.existsSync(), isFalse);
      });
    });

    testWidgets('a single failed photo goes again when its tile is tapped', (
      tester,
    ) async {
      uploadsFail = true;
      picker.answer = [photo('IMG_1.jpg')];
      await openRoom(tester);

      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the photo to fail',
        until: () => failedTiles() == 1,
      );
      expect(harness.sent, isEmpty);

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail));
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the retried photo to be sent',
      );

      expect(harness.sent.single['msgtype'], 'm.image');
      expect(find.text('Not sent. Tap to try again.'), findsNothing);
    });

    testWidgets('a single failed photo says so and goes again once back '
        'online', (tester) async {
      final status = StreamController<ConnectionStatus>.broadcast();
      addTearDown(status.close);
      uploadsFail = true;
      picker.answer = [photo('IMG_1.jpg')];
      await openRoom(
        tester,
        overrides: [
          connectionStatusProvider.overrideWith((ref) => status.stream),
        ],
      );
      status.add(ConnectionStatus.online);
      await harness.drive(tester, turns: 2);

      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the photo to fail',
        until: () => shows('Not sent. Tap to try again.'),
      );

      expect(harness.sent, isEmpty);
      expect(find.text('Not sent. Tap to try again.'), findsOneWidget);
      expect(find.text('Not sent. Try again.'), findsNothing);

      uploadsFail = false;
      status.add(ConnectionStatus.noInternet);
      await harness.drive(tester, turns: 2);
      expect(harness.sent, isEmpty);
      status.add(ConnectionStatus.online);
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the photo to go again once online',
      );

      expect(harness.sent.single['msgtype'], 'm.image');
    });
  });

  group('deleting while still sending', () {
    setUp(() => sendsGiveUpAtOnce = true);

    late Completer<void> heldUpload;
    late List<String> redacted;
    late int uploads;
    late bool laterUploadsFail;
    late int posted;
    late bool held;
    late bool postHeld;
    late Completer<void> heldConfig;
    late bool configHeld;
    late List<Event> placeholders;

    void holdUpload({
      required int afterPosts,
      bool holdPost = false,
      bool holdConfig = false,
    }) {
      placeholders = [];
      final sub = harness.client.onTimelineEvent.stream
          .where((e) => e.status.isSending)
          .map(
            (e) => Event.fromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
              e.room,
            ),
          )
          .listen(placeholders.add);
      addTearDown(sub.cancel);
      heldUpload = Completer<void>();
      redacted = [];
      uploads = 0;
      laterUploadsFail = false;
      posted = 0;
      held = false;
      postHeld = false;
      heldConfig = Completer<void>();
      configHeld = false;
      final respond = harness.respond!;
      harness.respond = (request) async {
        final path = request.url.path;
        if (holdConfig && !configHeld && path.endsWith('/media/config')) {
          configHeld = true;
          await heldConfig.future;
        }
        if (path.endsWith('/upload')) {
          uploads++;
          if (posted == afterPosts && !held) {
            held = true;
            await heldUpload.future;
          }
          if (posted == afterPosts && laterUploadsFail) {
            return http.Response(
              jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'boom'}),
              500,
            );
          }
        }
        if (path.contains('/send/m.room.message/')) {
          if (holdPost && !postHeld) {
            postHeld = true;
            await Completer<void>().future;
          }
          harness.sent.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response(
            jsonEncode({'event_id': '\$item${++posted}'}),
            200,
          );
        }
        if (path.contains('/redact/')) {
          redacted.add(
            Uri.decodeComponent(request.url.pathSegments.reversed.elementAt(1)),
          );
          return http.Response(jsonEncode({'event_id': r'$redaction'}), 200);
        }
        return respond(request);
      };
    }

    Future<void> drain(WidgetTester tester) => harness.drive(tester, turns: 30);

    Future<SharedPreferences> storedOnDisk() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs;
    }

    Future<Map<String, Object>> storedPreferences() async {
      final prefs = await storedOnDisk();
      return {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    }

    Future<DiscardedSends> discardRecord() async =>
        DiscardedSends(await storedOnDisk());

    Event asNotSent(Event placeholder) => Event.fromJson(
      jsonDecode(
        jsonEncode({
          ...placeholder.toJson(),
          'status': EventStatus.error.intValue,
        }),
      ) as Map<String, dynamic>,
      harness.room,
    );

    Future<void> restartOffline(
      WidgetTester tester, {
      required Map<String, Object> preferences,
      required List<Event> Function() events,
      required StreamController<ConnectionStatus> status,
    }) async {
      await tester.pumpWidget(const SizedBox());
      await openRoom(
        tester,
        db: _CachedFilesDatabase(),
        preferences: preferences,
        overrides: [
          connectionStatusProvider.overrideWith((ref) => status.stream),
        ],
        prepare: (_) => harness.db.events = events(),
      );
      status.add(ConnectionStatus.noInternet);
      await harness.drive(tester, turns: 2);
    }

    Iterable<String> sendsAfterRestart() => harness.requests.where(
      (path) => path.endsWith('/upload') || path.contains('/send/'),
    );

    Future<void> confirmDelete(
      WidgetTester tester,
      Finder row,
      String action,
    ) async {
      await tester.longPress(row, warnIfMissed: false);
      await harness.settle(tester);
      await tester.tap(find.widgetWithText(ListTile, action));
      await harness.settle(tester);
      await tester.tap(
        find.widgetWithText(
          TextButton,
          action.startsWith('Delete all') ? 'Delete all' : 'Delete',
        ),
      );
      await harness.settle(tester);
    }

    group('a gallery', () {
      Future<void> sendGalleryHoldingSecond(
        WidgetTester tester, {
        int photos = 3,
        bool reopenable = false,
      }) async {
        picker.answer = [for (var i = 0; i < photos; i++) photo('$i.jpg')];
        await openRoom(tester, reopenable: reopenable);
        holdUpload(afterPosts: 1);
        await choose(tester, 'Choose from gallery');
        await sendFromComposer(
          tester,
          tooltip: 'Send all',
          awaiting: 'the second photo to start uploading',
          until: () => held,
        );
        await harness.settle(tester);
      }

      Future<void> deleteGallery(WidgetTester tester, String action) =>
          confirmDelete(tester, find.byType(GalleryMessage), action);

      testWidgets('deletes what arrived, stops the photo on its way, and '
          'sends nothing more', (tester) async {
        await sendGalleryHoldingSecond(tester);

        await deleteGallery(tester, 'Delete all (2)');
        expect(redacted, [r'$item1']);

        heldUpload.complete();
        await drain(tester);

        expect(redacted, [r'$item1']);
        expect(harness.sent, hasLength(1));
        expect(uploads, 2);
        expect(find.byType(NotSentRow), findsNothing);
        expect(failedTiles(), 0);
      });

      testWidgets('Cancel lets every photo go', (tester) async {
        await sendGalleryHoldingSecond(tester);

        await tester.longPress(
          find.byType(GalleryMessage),
          warnIfMissed: false,
        );
        await harness.settle(tester);
        await tester.tap(find.widgetWithText(ListTile, 'Delete all (2)'));
        await harness.settle(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await harness.settle(tester);
        heldUpload.complete();
        await pumpUntil(
          tester,
          () => harness.sent.length == 3,
          reason: 'every photo to be sent',
        );

        expect(redacted, isEmpty);
      });

      testWidgets('drops its failed photos instead of offering them again', (
        tester,
      ) async {
        await sendGalleryHoldingSecond(tester, photos: 2);
        laterUploadsFail = true;
        heldUpload.complete();
        await pumpUntil(
          tester,
          () => failedTiles() == 1,
          reason: 'the second photo to fail',
        );

        await deleteGallery(tester, 'Delete');
        await drain(tester);

        expect(redacted, [r'$item1']);
        expect(failedTiles(), 0);
        expect(harness.sent, hasLength(1));
      });

      testWidgets('works from the chat opened again while the batch runs', (
        tester,
      ) async {
        await sendGalleryHoldingSecond(tester, reopenable: true);

        await tester.pageBack();
        await harness.settle(tester);
        await tester.tap(find.text('open'));
        await harness.settle(tester);
        await deleteGallery(tester, 'Delete all (2)');
        heldUpload.complete();
        await drain(tester);

        expect(redacted, [r'$item1']);
        expect(harness.sent, hasLength(1));
      });

      testWidgets('a photo going again after a restart is stopped', (
        tester,
      ) async {
        final status = StreamController<ConnectionStatus>.broadcast();
        addTearDown(status.close);
        Event galleryPhoto(String id, int index, EventStatus sendStatus) =>
            buildTestEvent(
              harness.room,
              eventId: id,
              senderId: '@me:example.org',
              originServerTs: DateTime(2026, 9, 20, 12, 5 + index),
              status: sendStatus,
              content: {
                'msgtype': 'm.image',
                'body': 'photo.jpg',
                'filename': 'photo.jpg',
                if (sendStatus.isSent) 'url': 'mxc://example.org/p$index',
                'info': {'w': 40, 'h': 30, 'mimetype': 'image/jpeg'},
                ...galleryGroupContent(id: 'g', index: index, count: 2),
              },
            );
        await openRoom(
          tester,
          db: _CachedFilesDatabase(),
          overrides: [
            connectionStatusProvider.overrideWith((ref) => status.stream),
          ],
          prepare: (_) => harness.db.events = [
            galleryPhoto('txn-2', 1, EventStatus.error)
              ..unsigned = {
                'transaction_id': 'txn-2',
                'extra_content': galleryGroupContent(
                  id: 'g',
                  index: 1,
                  count: 2,
                ),
              },
            galleryPhoto(r'$p1', 0, EventStatus.synced),
          ],
        );
        holdUpload(afterPosts: 0);
        status.add(ConnectionStatus.noInternet);
        await harness.drive(tester, turns: 2);
        status.add(ConnectionStatus.online);
        await pumpUntil(
          tester,
          () => held,
          reason: 'the photo to start uploading again',
        );
        await harness.settle(tester);

        await deleteGallery(tester, 'Delete all (2)');
        heldUpload.complete();
        await drain(tester);

        expect(redacted, [r'$p1']);
        expect(harness.sent, isEmpty);
        expect(find.byType(NotSentRow), findsNothing);
      });

      testWidgets('stays deleted after a restart: the photo left on its way '
          'is dropped, not sent again', (tester) async {
        final status = StreamController<ConnectionStatus>.broadcast();
        addTearDown(status.close);
        await sendGalleryHoldingSecond(tester);
        final onItsWay = placeholders.last;
        await deleteGallery(tester, 'Delete all (2)');
        final stored = await storedPreferences();

        await restartOffline(
          tester,
          preferences: stored,
          events: () => [asNotSent(onItsWay), harness.message(r'$m1')],
          status: status,
        );
        status.add(ConnectionStatus.online);
        await drain(tester);

        expect(find.byType(NotSentRow), findsNothing);
        expect(sendsAfterRestart(), isEmpty);
        expect(
          (await storedPreferences()).keys,
          everyElement(isNot(startsWith('chat.'))),
        );
      });
    });

    testWidgets('a photo deleted while it uploads stops there, and nothing '
        'reaches the chat', (tester) async {
      picker.answer = [photo('a.jpg')];
      await openRoom(tester);
      holdUpload(afterPosts: 0);
      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the photo to start uploading',
        until: () => held,
      );
      await harness.settle(tester);

      await confirmDelete(tester, find.byType(ImageMessage), 'Delete');
      expect(find.byType(ImageMessage), findsNothing);
      heldUpload.complete();
      await drain(tester);

      expect(harness.sent, isEmpty);
      expect(redacted, isEmpty);
      expect(uploads, 1);
      expect(failedTiles(), 0);
      expect(find.byType(ImageMessage), findsNothing);
      expect(find.byType(NotSentRow), findsNothing);
      expect(
        (await discardRecord()).contains(harness.room, [
          placeholders.first.eventId,
        ]),
        isFalse,
      );
    });

    testWidgets('a photo deleted while its send still runs stays gone when '
        'the send shows it again', (tester) async {
      picker.answer = [photo('a.jpg')];
      await openRoom(tester);
      holdUpload(afterPosts: 99, holdConfig: true);
      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the photo to wait for the media limits',
        until: () => configHeld,
      );
      await harness.settle(tester);

      await confirmDelete(tester, find.byType(ImageMessage), 'Delete');
      harness.client.onTimelineEvent.add(placeholders.single);
      await harness.settle(tester);

      expect(find.byType(ImageMessage), findsNothing);
      expect(find.byType(NotSentRow), findsNothing);

      heldConfig.complete();
      await drain(tester);

      expect(find.byType(ImageMessage), findsNothing);
      expect(find.byType(NotSentRow), findsNothing);
      expect(uploads, 0);
      expect(harness.sent, isEmpty);
    });

    testWidgets('a photo of a batch deleted while it uploads, shown on its '
        'own, stops alone: the rest still goes', (tester) async {
      picker.answer = [photo('a.jpg'), photo('b.jpg'), photo('c.jpg')];
      await openRoom(tester);
      holdUpload(afterPosts: 0);
      await choose(tester, 'Choose from gallery');
      await sendFromComposer(
        tester,
        tooltip: 'Send all',
        awaiting: 'the first photo to start uploading',
        until: () => held,
      );
      await harness.settle(tester);

      await confirmDelete(tester, find.byType(ImageMessage), 'Delete');
      await pumpUntil(
        tester,
        () => harness.sent.length == 2,
        reason: 'the rest of the batch to be sent',
      );
      heldUpload.complete();
      await drain(tester);

      expect(
        [for (final sent in harness.sent) galleryOf(sent)!['index']],
        [1, 2],
      );
      expect(redacted, isEmpty);
    });

    testWidgets('deleting the one photo shown of a batch still being '
        'prepared leaves the rest to go', (tester) async {
      final probe = Completer<void>();
      var probes = 0;
      picker.answer = [photo('a.jpg'), _video('b.mp4'), photo('c.jpg')];
      await openRoom(tester);
      holdUpload(afterPosts: 99);
      beforeVideoTool = (method) async {
        if (method == 'probe' && posted == 1 && probes++ == 0) {
          await probe.future;
        }
      };
      await choose(tester, 'Choose from gallery');
      await sendFromComposer(
        tester,
        tooltip: 'Send all',
        awaiting: 'the video to start being prepared',
        until: () => probes == 1,
      );
      await harness.settle(tester);

      await confirmDelete(tester, find.byType(ImageMessage), 'Delete');
      probe.complete();
      await pumpUntil(
        tester,
        () => harness.sent.length == 3,
        reason: 'the rest of the batch to be sent',
      );

      expect(redacted, [r'$item1']);
    });

    Future<Event> sendFileShownAsNotSent(WidgetTester tester) async {
      files.picked = [
        FakePickedFile('a.pdf', Uint8List.fromList([1])),
      ];
      await openRoom(tester);
      holdUpload(afterPosts: 0);
      await choose(tester, 'Choose file');
      await pumpUntil(
        tester,
        () => held,
        reason: 'the file to start uploading',
      );
      final onItsWay = placeholders.first;
      harness.client.onTimelineEvent.add(asNotSent(onItsWay));
      await harness.settle(tester);
      return onItsWay;
    }

    testWidgets('a file shown as not sent while it still uploads is stopped '
        'there', (tester) async {
      final onItsWay = await sendFileShownAsNotSent(tester);
      expect(find.byType(NotSentRow), findsOneWidget);

      await confirmDelete(tester, find.byType(FileMessage), 'Delete');
      heldUpload.complete();
      await drain(tester);

      expect(redacted, isEmpty);
      expect(harness.sent, isEmpty);
      expect(find.byType(FileMessage), findsNothing);
      expect(
        (await discardRecord()).contains(harness.room, [onItsWay.eventId]),
        isFalse,
      );
    });

    testWidgets('a file deleted while its message is being posted stays '
        'deleted after a restart, and is never sent again', (tester) async {
      final status = StreamController<ConnectionStatus>.broadcast();
      addTearDown(status.close);
      files.picked = [
        FakePickedFile('a.pdf', Uint8List.fromList([1])),
      ];
      await openRoom(tester);
      holdUpload(afterPosts: 99, holdPost: true);
      await choose(tester, 'Choose file');
      await pumpUntil(
        tester,
        () => postHeld,
        reason: 'the file message to be posted',
      );
      final onItsWay = placeholders.first;
      await confirmDelete(tester, find.byType(FileMessage), 'Delete');
      expect(find.byType(FileMessage), findsNothing);
      final stored = await storedPreferences();

      await restartOffline(
        tester,
        preferences: stored,
        events: () => [asNotSent(onItsWay), harness.message(r'$m1')],
        status: status,
      );
      expect(find.byType(FileMessage), findsNothing);
      status.add(ConnectionStatus.online);
      await drain(tester);

      expect(sendsAfterRestart(), isEmpty);
      expect(
        (await discardRecord()).contains(harness.room, [onItsWay.eventId]),
        isFalse,
      );
      await tester.pump(sendStallLimit);
    });

    testWidgets('a record that matches nothing unsent is cleared when the '
        'chat opens', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final seeded = await SharedPreferences.getInstance();
      final elsewhere = buildTestRoom(
        buildTestClient(userId: '@me:example.org'),
      );
      await DiscardedSends(seeded).add(elsewhere, 'txn-long-gone');
      final stored = await storedPreferences();
      expect(stored, isNotEmpty);

      await openRoom(tester, preferences: stored);

      expect(
        (await discardRecord()).contains(harness.room, ['txn-long-gone']),
        isFalse,
      );
      expect(
        (await storedPreferences()).keys,
        everyElement(isNot(startsWith('chat.'))),
      );
    });
  });

  group('a send that stops moving', () {
    setUp(() => sendsGiveUpAtOnce = true);

    late bool asked;

    Future<void> sendPhotoStuckAt(
      WidgetTester tester,
      bool Function(String path) stuck,
    ) async {
      picker.answer = [photo('a.jpg')];
      await openRoom(tester);
      asked = false;
      final respond = harness.respond!;
      harness.respond = (request) {
        if (asked || !stuck(request.url.path)) return respond(request);
        asked = true;
        return Completer<http.Response?>().future;
      };
      await choose(tester, 'Take photo');
      await sendFromComposer(
        tester,
        awaiting: 'the request that never gets an answer',
        until: () => asked,
      );
      await tester.pump(sendStallLimit);
      await harness.settle(tester);
    }

    testWidgets('a photo whose upload never gets an answer fails once '
        'nothing has moved for the stall limit, and goes again when tapped', (
      tester,
    ) async {
      await sendPhotoStuckAt(tester, (path) => path.endsWith('/upload'));

      expect(failedTiles(), 1);
      expect(harness.sent, isEmpty);
      await tester.tap(find.byType(GalleryFailedThumbnail));
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the photo to go again',
      );
      expect(harness.sent.single['msgtype'], 'm.image');
    });

    testWidgets('a photo stuck fetching the media limits fails the same '
        'way', (tester) async {
      await sendPhotoStuckAt(tester, (path) => path.endsWith('/media/config'));

      expect(failedTiles(), 1);
      expect(harness.sent, isEmpty);
    });

    testWidgets('a photo whose message post never gets an answer shows as '
        'not sent', (tester) async {
      await sendPhotoStuckAt(
        tester,
        (path) => path.contains('/send/m.room.message/'),
      );

      expect(find.byType(NotSentRow), findsOneWidget);
      expect(failedTiles(), 0);
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
      files.pickError = PlatformException(code: 'unknown_path');
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
      await sendFromComposer(
        tester,
        awaiting: 'the video to be sent',
        until: () => harness.sent.isNotEmpty,
      );

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
      await sendFromComposer(
        tester,
        awaiting: 'the video to be sent',
        until: () => harness.sent.isNotEmpty,
      );

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
      picker.answer = [photo('a.jpg'), _video('b.mp4')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      expect(find.byType(MediaCaptionComposerPage), findsOneWidget);
      await sendFromComposer(
        tester,
        tooltip: 'Send all',
        awaiting: 'the photo and the video to be sent',
        until: () => harness.sent.length == 2,
      );

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
      picker.answer = [photo('a.jpg'), _video('b.mp4')];
      await openRoom(tester);

      await choose(tester, 'Choose from gallery');
      await sendFromComposer(
        tester,
        tooltip: 'Send all',
        awaiting: 'the photo and the video to fail',
        until: () => failedTiles() == 2,
      );
      expect(find.byType(GalleryFailedThumbnail), findsNWidgets(2));

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail).last);
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the retried video to be sent',
      );

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
    Finder attachSpinner() => find.descendant(
      of: find.byType(MessageComposer),
      matching: find.byType(CircularProgressIndicator),
    );

    testWidgets('a file is sent under its name', (tester) async {
      files.picked = [
        FakePickedFile('notes.pdf', Uint8List.fromList([1, 2])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the file to be sent',
      );

      expect(harness.sent.single['msgtype'], 'm.file');
      expect(harness.sent.single['body'], 'notes.pdf');
    });

    testWidgets('every picked file is sent, not just one', (tester) async {
      files.picked = [
        FakePickedFile('a.pdf', Uint8List.fromList([1])),
        FakePickedFile('b.txt', Uint8List.fromList([2])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await pumpUntil(
        tester,
        () => harness.sent.length == 2,
        reason: 'both files to be sent',
      );

      expect([for (final s in harness.sent) s['body']], ['a.pdf', 'b.txt']);
    });

    testWidgets('a sent file leaves no picker copy behind', (tester) async {
      final copy = File('${temp.path}/notes.pdf')..writeAsBytesSync([1, 2]);
      files.picked = [
        FakePickedFile(
          'notes.pdf',
          Uint8List.fromList([1, 2]),
          path: copy.path,
        ),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty && !copy.existsSync(),
        reason: 'the file to be sent and its copy removed',
      );

      expect(harness.sent.single['body'], 'notes.pdf');
      expect(copy.existsSync(), isFalse);
    });

    testWidgets('attach spins while the picked file is on its way', (
      tester,
    ) async {
      files.copying = Completer<void>();
      files.picked = [
        FakePickedFile('notes.pdf', Uint8List.fromList([1])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');

      expect(attachSpinner(), findsOneWidget);
      expect(harness.sent, isEmpty);

      files.copying!.complete();
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty,
        reason: 'the file to be sent',
      );

      expect(attachSpinner(), findsNothing);
      expect(harness.sent.single['body'], 'notes.pdf');
    });

    testWidgets('a pick that fails on its way stops the spin and says so', (
      tester,
    ) async {
      files.copying = Completer<void>();
      files.pickError = PlatformException(code: 'unknown_path');
      await openRoom(tester);

      await choose(tester, 'Choose file');
      files.copying!.complete();
      await pumpUntil(
        tester,
        () => shows('Files did not open. Try again.'),
        reason: 'the failed pick to be reported',
      );

      expect(attachSpinner(), findsNothing);
      expect(find.text('Files did not open. Try again.'), findsOneWidget);
    });

    testWidgets('nothing picked sends nothing', (tester) async {
      await openRoom(tester);

      await choose(tester, 'Choose file');

      expect(harness.sent, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed upload says so', (tester) async {
      uploadsFail = true;
      files.picked = [
        FakePickedFile('a.pdf', Uint8List.fromList([1])),
      ];
      await openRoom(tester);

      await choose(tester, 'Choose file');
      await pumpUntil(
        tester,
        () => shows('Not sent. Try again.'),
        reason: 'the failed upload to be reported',
      );

      expect(find.text('Not sent. Try again.'), findsOneWidget);
      expect(find.byType(NotSentRow), findsNothing);
    });
  });

  group('location', () {
    Future<void> chooseLocation(WidgetTester tester) async {
      await choose(tester, 'Location');
      await pumpUntil(
        tester,
        () => shows('Send location'),
        reason: 'the location to be found',
      );
    }

    Future<void> shareLocation(
      WidgetTester tester, {
      required String awaiting,
      required bool Function() until,
    }) async {
      await chooseLocation(tester);
      await tester.tap(find.text('Send location'));
      await pumpUntil(tester, until, reason: awaiting);
    }

    Future<void> openRoomForLocation(WidgetTester tester) => openRoom(
      tester,
      overrides: [mapTilesProvider.overrideWith((ref) async => null)],
    );

    testWidgets('the found location is sent as an MSC3488 pin of me', (
      tester,
    ) async {
      await openRoomForLocation(tester);

      await shareLocation(
        tester,
        awaiting: 'the pin to be sent',
        until: () => harness.sent.isNotEmpty,
      );

      final sent = harness.sent.single;
      expect(sent['msgtype'], 'm.location');
      expect(sent['geo_uri'], startsWith('geo:52.37,4.89'));
      expect(sent['body'], startsWith('Location: 52.37'));
      expect(sent['org.matrix.msc3488.location'], {'uri': sent['geo_uri']});
      expect(sent['org.matrix.msc3488.asset'], {'type': 'm.self'});
      expect(sent['org.matrix.msc3488.ts'], isA<int>());
    });

    testWidgets('a refused send says so', (tester) async {
      locationFails = true;
      await openRoomForLocation(tester);

      await shareLocation(
        tester,
        awaiting: 'the refusal to be reported',
        until: () => shows('Location not sent. Try again.'),
      );

      expect(find.text('Location not sent. Try again.'), findsOneWidget);
    });

    testWidgets('alone in the chat, the menu still offers Location', (
      tester,
    ) async {
      await openRoom(
        tester,
        prepare: (room) => room.setState(
          User('@bob:example.org', membership: 'leave', room: room),
        ),
      );

      await openAttachMenu(tester);

      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.byTooltip('Voice call'), findsNothing);
    });

    group('live', () {
      late _StartRecordingSharing sharing;

      Future<void> openEncryptedRoom(WidgetTester tester) => openRoom(
        tester,
        encrypting: true,
        overrides: [
          mapTilesProvider.overrideWith((ref) async => null),
          liveLocationSharingProvider.overrideWith((ref) {
            sharing = _StartRecordingSharing(ref.watch(matrixClientProvider));
            ref.onDispose(sharing.dispose);
            return sharing;
          }),
        ],
        prepare: (room) {
          room.setState(
            buildTestEvent(
              room,
              eventId: r'$encryption',
              senderId: '@me:example.org',
              type: EventTypes.Encryption,
              stateKey: '',
              content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
            ),
          );
          room.setState(
            buildTestEvent(
              room,
              eventId: r'$power',
              senderId: '@me:example.org',
              type: EventTypes.RoomPowerLevels,
              stateKey: '',
              content: {
                'users': {'@me:example.org': 100},
              },
            ),
          );
        },
      );

      Future<void> startLive(
        WidgetTester tester, {
        required String awaiting,
        required bool Function() until,
      }) async {
        await chooseLocation(tester);
        await tester.tap(find.text('Share live location'));
        await pumpUntil(
          tester,
          () => shows('Start sharing'),
          reason: 'the share length to be offered',
        );
        await tester.tap(find.text('Start sharing'));
        await pumpUntil(tester, until, reason: awaiting);
      }

      testWidgets('shares the found location for the chosen time', (
        tester,
      ) async {
        await openEncryptedRoom(tester);

        await startLive(
          tester,
          awaiting: 'the share to start',
          until: () => sharing.started.isNotEmpty,
        );

        final started = sharing.started.single;
        expect(started.roomId, harness.room.id);
        expect(started.duration, LiveLocationDuration.quarterHour);
        expect(started.first.geo.latitude, 52.37);
        expect(started.first.geo.longitude, 4.89);
      });

      testWidgets('a share that cannot start says why', (tester) async {
        await openEncryptedRoom(tester);
        sharing.refusal = LiveShareStartFailure.captureUnavailable;
        const refusal =
            'Live location could not start. Check that location is on, '
            'then try again.';

        await startLive(
          tester,
          awaiting: 'the refusal to be explained',
          until: () => shows(refusal),
        );

        expect(find.text(refusal), findsOneWidget);
      });
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
    await pumpUntil(
      tester,
      () => harness.sent.isNotEmpty,
      reason: 'the message to go again once online',
    );

    expect(harness.sent.single['body'], 'still there?');
  });
}

class _StartRecordingSharing extends LiveLocationSharing {
  _StartRecordingSharing(Client client)
    : super(
        client: client,
        capture: FakeLiveLocationCapture(),
        isOffline: () => false,
        recipients: (_) async => const [],
      );

  final started =
      <({String roomId, LiveLocationDuration duration, LivePosition first})>[];
  LiveShareStartFailure? refusal;

  @override
  Future<void> start(
    Room room,
    LiveLocationDuration duration,
    LivePosition first,
  ) async {
    if (refusal case final reason?) throw LiveShareStartException(reason);
    started.add((roomId: room.id, duration: duration, first: first));
  }
}
