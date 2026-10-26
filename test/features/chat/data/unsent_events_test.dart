import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/features/chat/data/unsent_events.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

class _SendingDatabase extends StoredEventsFakeDatabaseApi
    with SendCapableDatabase {}

void main() {
  late _SendingDatabase db;
  late List<http.Request> requests;
  late Room room;
  final noon = DateTime(2026, 9, 20, 12);
  final later = noon.add(const Duration(minutes: 1));

  setUp(() {
    db = _SendingDatabase();
    requests = [];
    final client = buildTestClient(
      userId: '@me:x',
      database: db,
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'event_id': r'$new'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'token';
    room = buildTestRoom(client)..partial = false;
  });

  Event message(
    EventStatus status, {
    String senderId = '@me:x',
    String id = r'$1',
    DateTime? at,
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: senderId,
    status: status,
    originServerTs: at ?? noon,
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
  );

  Event edit(
    String id,
    String target,
    EventStatus status, {
    required DateTime at,
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: '@me:x',
    status: status,
    originServerTs: at,
    content: {
      'msgtype': MessageTypes.Text,
      'body': '* fixed',
      'm.new_content': {'msgtype': MessageTypes.Text, 'body': 'fixed'},
      'm.relates_to': {'rel_type': RelationshipTypes.edit, 'event_id': target},
    },
  );

  Future<Timeline> timelineOf(List<Event> events) async {
    db.events = events;
    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    return timeline;
  }

  test('an own message the server refused is not sent', () {
    expect(isNotSent(message(EventStatus.error)), isTrue);
  });

  test('a message still on its way, or delivered, is not "not sent"', () {
    expect(isNotSent(message(EventStatus.sending)), isFalse);
    expect(isNotSent(message(EventStatus.sent)), isFalse);
  });

  test("someone else's event is never ours to resend", () {
    expect(isNotSent(message(EventStatus.error, senderId: '@a:x')), isFalse);
  });

  test('a call message that failed is never offered again, since a late '
      'copy would describe a call that is over', () async {
    for (final msgtype in [
      callInviteMsgtype,
      callDeclineMsgtype,
      callSummaryMsgtype,
    ]) {
      final failed = buildTestEvent(
        room,
        eventId: '\$$msgtype',
        senderId: '@me:x',
        status: EventStatus.error,
        content: {'msgtype': msgtype, 'body': 'call', 'call_id': 'c1'},
      );

      expect(isNotSent(failed), isFalse, reason: msgtype);
      expect(
        notSentOwnEvents(await timelineOf([failed])),
        isEmpty,
        reason: msgtype,
      );
    }
  });

  test('notSentOwnEvents keeps only own failed events, oldest first, so '
      'they go again in the order they were written', () async {
    final older = message(EventStatus.error, id: 'txn-a', at: noon);
    final newer = message(
      EventStatus.error,
      id: 'txn-b',
      at: noon.add(const Duration(minutes: 1)),
    );

    final selected = notSentOwnEvents(
      await timelineOf([
        newer,
        message(EventStatus.sent, id: r'$sent'),
        message(EventStatus.error, senderId: '@a:x', id: r'$theirs'),
        message(EventStatus.sending, id: 'txn-pending'),
        older,
      ]),
    );

    expect(selected.map((e) => e.eventId), ['txn-a', 'txn-b']);
  });

  group('a failed edit', () {
    final latest = noon.add(const Duration(minutes: 2));

    test('goes again while its message shows it', () async {
      final failed = edit('txn-edit', r'$1', EventStatus.error, at: later);

      final selected = notSentOwnEvents(
        await timelineOf([failed, message(EventStatus.synced)]),
      );

      expect(selected.map((e) => e.eventId), ['txn-edit']);
    });

    test('never goes again once a newer edit replaced it', () async {
      final selected = notSentOwnEvents(
        await timelineOf([
          edit(r'$edit2', r'$1', EventStatus.synced, at: latest),
          edit('txn-edit', r'$1', EventStatus.error, at: later),
          message(EventStatus.synced),
        ]),
      );

      expect(selected, isEmpty);
    });

    test('never goes again once its message is deleted', () async {
      final deleted = message(EventStatus.synced)
        ..setRedactionEvent(
          buildTestEvent(
            room,
            eventId: r'$redaction',
            senderId: '@me:x',
            type: EventTypes.Redaction,
            originServerTs: latest,
          ),
        );

      final selected = notSentOwnEvents(
        await timelineOf([
          edit('txn-edit', r'$1', EventStatus.error, at: later),
          deleted,
        ]),
      );

      expect(selected, isEmpty);
    });
  });

  group('notSentBehind', () {
    test('a row drawn from a failed edit is not sent, and the edit itself is '
        'what goes again', () async {
      final original = message(EventStatus.synced);
      final timeline = await timelineOf([
        edit('txn-edit', r'$1', EventStatus.error, at: later),
        original,
      ]);

      final unsent = notSentBehind(original, timeline);

      expect(unsent?.eventId, 'txn-edit');
      expect(unsent?.content['m.new_content'], isNotNull);
    });

    test('a row drawn from a sent edit is sent', () async {
      final original = message(EventStatus.synced);
      final timeline = await timelineOf([
        edit(r'$edit', r'$1', EventStatus.synced, at: later),
        original,
      ]);

      expect(notSentBehind(original, timeline), isNull);
    });

    test('a failed message is its own unsent event', () async {
      final failed = message(EventStatus.error, id: 'txn-1');
      final timeline = await timelineOf([failed]);

      expect(notSentBehind(failed, timeline), same(failed));
    });

    test('a message still on its way is not "not sent"', () async {
      final sending = message(EventStatus.sending, id: 'txn-1');
      final timeline = await timelineOf([sending]);

      expect(notSentBehind(sending, timeline), isNull);
    });
  });

  group('resendUnsent', () {
    test('a failed reaction goes again as a reaction', () async {
      final failed = buildTestEvent(
        room,
        eventId: 'txn-react',
        senderId: '@me:x',
        type: EventTypes.Reaction,
        status: EventStatus.error,
        originServerTs: noon,
        content: {
          'm.relates_to': {
            'rel_type': RelationshipTypes.reaction,
            'event_id': r'$1',
            'key': '👍',
          },
        },
      );
      failed.unsigned = {'transaction_id': 'txn-react'};

      await resendUnsent(failed);

      expect(requests.single.url.path, contains('/send/m.reaction/txn-react'));
    });

    test('something already delivered is not sent again', () async {
      await resendUnsent(message(EventStatus.synced));

      expect(requests, isEmpty);
    });
  });
}
