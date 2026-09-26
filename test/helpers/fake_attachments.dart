import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';

import 'fake_matrix.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _MediaDatabase extends FakeDatabaseApi {
  @override
  int get maxFileSize => 0;

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> content,
  ) async {}
}

class AttachmentServer {
  AttachmentServer._(this.root);

  final Directory root;
  final downloads = <Uri>[];
  Uint8List served = onePixelPng;
  final missing = <String>{};
  late final Client client;
  late final Room room;

  static String mediaId(String eventId) => eventId.substring(1);

  void goneFromServer(Event event) => missing.add(mediaId(event.eventId));

  Directory get cacheDirectory => Directory('${root.path}/cache');

  Directory get temporaryDirectory => Directory('${root.path}/temp');

  Event attachment({
    String eventId = r'$attachment',
    String msgtype = MessageTypes.Image,
    String body = 'photo.png',
    String? filename,
    String mimetype = 'image/png',
  }) => buildTestEvent(
    room,
    eventId: eventId,
    senderId: '@bob:example.org',
    status: EventStatus.synced,
    content: {
      'msgtype': msgtype,
      'body': body,
      'filename': ?filename,
      'url': 'mxc://example.org/${mediaId(eventId)}',
      'info': {'mimetype': mimetype},
    },
  );
}

AttachmentServer installAttachmentServer() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final server = AttachmentServer._(
    Directory.systemTemp.createTempSync('zuno_attachments'),
  );
  server.cacheDirectory.createSync();
  server.temporaryDirectory.createSync();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    _pathProvider,
    (call) async => switch (call.method) {
      'getApplicationCacheDirectory' => server.cacheDirectory.path,
      'getTemporaryDirectory' => server.temporaryDirectory.path,
      _ => null,
    },
  );

  server.client = buildTestClient(
    userId: '@me:example.org',
    database: _MediaDatabase(),
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/versions')) {
        return http.Response(
          jsonEncode({
            'versions': ['v1.11'],
          }),
          200,
        );
      }
      server.downloads.add(request.url);
      if (server.missing.any((id) => request.url.path.endsWith('/$id'))) {
        return http.Response(
          jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
          404,
        );
      }
      return http.Response.bytes(server.served, 200);
    }),
  );
  server.client.homeserver = Uri.parse('https://example.org');
  server.client.bearerToken = 'token';
  server.room = buildTestRoom(server.client);

  AttachmentCache.instance.clear();
  addTearDown(() async {
    AttachmentCache.instance.clear();
    await DiskAttachmentCache.instance.clear();
    messenger.setMockMethodCallHandler(_pathProvider, null);
    if (server.root.existsSync()) server.root.deleteSync(recursive: true);
  });
  return server;
}

Future<void> pumpWhileFetching(
  WidgetTester tester, {
  int rounds = 50,
  bool Function()? until,
}) async {
  for (var i = 0; i < rounds && !(until?.call() ?? false); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

class FakeFilePicker extends FilePickerPlatform {
  Uri? answer = Uri.parse('content://downloads/1');
  final saved = <({String fileName, Uint8List bytes, String mimeType})>[];

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved.add((fileName: fileName, bytes: bytes, mimeType: mimeType));
    return answer;
  }
}

class DeviceFakes {
  DeviceFakes._();

  final gallery = <MethodCall>[];
  final galleryFilesPresent = <bool>[];
  final shared = <Map<Object?, Object?>>[];
  final picker = FakeFilePicker();
  bool galleryRefuses = false;
}

DeviceFakes installDeviceFakes() {
  final fakes = DeviceFakes._();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const gal = MethodChannel('gal');
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  messenger.setMockMethodCallHandler(gal, (call) async {
    if (call.method == 'hasAccess' || call.method == 'requestAccess') {
      return true;
    }
    if (fakes.galleryRefuses) {
      throw PlatformException(code: 'NOT_SUPPORTED_FORMAT');
    }
    fakes.gallery.add(call);
    if (call.method == 'putVideo') {
      final path = (call.arguments as Map)['path'] as String;
      fakes.galleryFilesPresent.add(File(path).existsSync());
    }
    return null;
  });
  messenger.setMockMethodCallHandler(share, (call) async {
    fakes.shared.add(call.arguments as Map<Object?, Object?>);
    return 'dev.fluttercommunity.plus/share/success';
  });
  final originalPicker = FilePickerPlatform.instance;
  FilePickerPlatform.instance = fakes.picker;
  addTearDown(() {
    messenger.setMockMethodCallHandler(gal, null);
    messenger.setMockMethodCallHandler(share, null);
    FilePickerPlatform.instance = originalPicker;
  });
  return fakes;
}
