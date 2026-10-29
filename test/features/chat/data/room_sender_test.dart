import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/features/chat/data/discarded_sends.dart';
import 'package:zuno/features/chat/data/room_sender.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';

void main() {
  late AttachmentServer server;
  late List<String> said;
  late Object? configFailure;
  late RoomSender sender;

  setUp(() async {
    said = [];
    configFailure = null;
    silenceMethodChannels(['zuno/upload_service']);
    SharedPreferences.setMockInitialValues({});
    server = installAttachmentServer(database: SendingFakeDatabaseApi())
      ..respond = (request) async {
        final path = request.url.path;
        if (path.endsWith('/config')) {
          final failure = configFailure;
          if (failure != null) throw failure;
          return http.Response('{}', 200);
        }
        if (path.endsWith('/upload')) {
          return http.Response(
            jsonEncode({'content_uri': 'mxc://example.org/uploaded'}),
            200,
          );
        }
        if (path.contains('/send/')) {
          return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
        }
        return null;
      };
    server.room.partial = false;
    sender = RoomSender(
      room: server.room,
      discarded: DiscardedSends(await SharedPreferences.getInstance()),
      reduceMediaSize: () => false,
      chatOpen: () => false,
      say: said.add,
    );
    addTearDown(sender.dispose);
  });

  Future<void> sendNotes() =>
      sender.sendFile(utf8.encode('notes'), name: 'notes.txt');

  test('a file goes out and says nothing', () async {
    await sendNotes();

    expect(said, isEmpty);
  });

  test(
    'a file that fails offline says so and to check the connection',
    () async {
      configFailure = const SocketException('offline');

      await sendNotes();

      expect(said, ['Not sent. Check your connection and try again.']);
    },
  );

  test('a file that fails online says only that it did not send', () async {
    configFailure = MatrixException.fromJson({
      'errcode': 'M_UNKNOWN',
      'error': 'no',
    });

    await sendNotes();

    expect(said, ['Not sent. Try again.']);
  });

  test(
    'a voice message that fails offline says to check the connection',
    () async {
      configFailure = const SocketException('offline');

      await sender.sendVoice(
        utf8.encode('ogg'),
        duration: const Duration(seconds: 2),
        waveform: const [1, 2, 3],
      );

      expect(said, [
        'Voice message not sent. Check your connection and try again.',
      ]);
    },
  );
}
