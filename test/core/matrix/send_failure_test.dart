import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/send_failure.dart';

import '../../helpers/fake_matrix.dart';

class _PlaceholderDatabase extends FakeDatabaseApi {
  Event? stored;
  Object? lookupError;
  final removed = <String>[];

  @override
  Future<Event?> getEventById(String eventId, Room room) async {
    if (lookupError case final error?) throw error;
    return stored?.eventId == eventId ? stored : null;
  }

  @override
  Future<void> removeEvent(String eventId, String roomId) async =>
      removed.add(eventId);
}

void main() {
  final client = buildTestClient(userId: '@me:example.org');
  final room = buildTestRoom(client);

  Event withStatus(EventStatus status) => Event(
    eventId: 'txid-1',
    type: EventTypes.Message,
    senderId: '@me:example.org',
    originServerTs: DateTime.now(),
    content: const {'msgtype': 'm.video', 'body': 'video.mp4'},
    status: status,
    room: room,
  );

  group('isDiscardablePlaceholder', () {
    test('a placeholder still sending or already failed is discardable', () {
      expect(isDiscardablePlaceholder(withStatus(EventStatus.sending)), isTrue);
      expect(isDiscardablePlaceholder(withStatus(EventStatus.error)), isTrue);
    });

    test('a sent event is never touched', () {
      expect(isDiscardablePlaceholder(withStatus(EventStatus.sent)), isFalse);
      expect(isDiscardablePlaceholder(withStatus(EventStatus.synced)), isFalse);
    });

    test('nothing to discard when the event is missing', () {
      expect(isDiscardablePlaceholder(null), isFalse);
    });
  });

  test('tooLargeToSendMessage names the server limit in whole megabytes', () {
    expect(
      tooLargeToSendMessage(FileTooBigMatrixException(110000000, 52428800)),
      'Too large to send. The limit is 52 MB.',
    );
  });

  group('discardSendPlaceholder', () {
    late _PlaceholderDatabase db;
    late Room placeholderRoom;

    setUp(() {
      db = _PlaceholderDatabase();
      final client = buildTestClient(
        userId: '@me:example.org',
        database: db,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
            404,
          ),
        ),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'token';
      placeholderRoom = buildTestRoom(client);
    });

    Event stored(EventStatus status) => db.stored = Event(
      eventId: 'txid-1',
      type: EventTypes.Message,
      senderId: '@me:example.org',
      originServerTs: DateTime.now(),
      content: const {'msgtype': 'm.video', 'body': 'video.mp4'},
      status: status,
      room: placeholderRoom,
    );

    test('removes a placeholder that failed to send', () async {
      stored(EventStatus.error);

      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, ['txid-1']);
    });

    test('keeps an event the server already has', () async {
      stored(EventStatus.sent);

      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, isEmpty);
    });

    test('does nothing when the placeholder is already gone', () async {
      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, isEmpty);
    });

    test('does nothing when the lookup fails', () async {
      stored(EventStatus.error);
      db.lookupError = StateError('database closed');

      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, isEmpty);
    });
  });
}
