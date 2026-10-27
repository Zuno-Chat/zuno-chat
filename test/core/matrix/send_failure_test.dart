import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/send_failure.dart';

import '../../helpers/fake_http.dart';
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
    originServerTs: clock.now(),
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
      tooLargeToSendMessage(
        englishLocalizations,
        FileTooBigMatrixException(110000000, 52428800),
      ),
      'Too large to send. The limit is 52 MB.',
    );
  });

  group('discardSendPlaceholder', () {
    late _PlaceholderDatabase db;
    late Room placeholderRoom;
    late List<http.Request> requests;

    setUp(() {
      db = _PlaceholderDatabase();
      requests = [];
      final client = buildTestClient(
        userId: '@me:example.org',
        database: db,
        httpClient: FakeHttpClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
            404,
          );
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'token';
      placeholderRoom = buildTestRoom(client);
    });

    Event stored(EventStatus status) => db.stored = Event(
      eventId: 'txid-1',
      type: EventTypes.Message,
      senderId: '@me:example.org',
      originServerTs: clock.now(),
      content: const {'msgtype': 'm.video', 'body': 'video.mp4'},
      status: status,
      room: placeholderRoom,
    );

    test('removes a placeholder that failed to send', () async {
      stored(EventStatus.error);

      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, ['txid-1']);
    });

    test('a send that never showed a placeholder asks nobody', () async {
      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, isEmpty);
      expect(requests, isEmpty);
    });

    test('does nothing when the lookup fails', () async {
      stored(EventStatus.error);
      db.lookupError = StateError('database closed');

      await discardSendPlaceholder(placeholderRoom, 'txid-1');

      expect(db.removed, isEmpty);
    });
  });
}
