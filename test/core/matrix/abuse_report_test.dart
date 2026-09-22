import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/abuse_report.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  group('reportReasonText', () {
    test('is the bare category without a note', () {
      expect(reportReasonText(ReportReason.spam), 'spam');
    });

    test('appends a trimmed note', () {
      expect(
        reportReasonText(ReportReason.harassment, note: '  keeps insulting  '),
        'harassment: keeps insulting',
      );
    });

    test('names the room a person was reported from', () {
      expect(
        reportReasonText(
          ReportReason.illegal,
          note: 'see photo',
          roomId: '!room:example.org',
        ),
        'illegal: see photo (room !room:example.org)',
      );
    });
  });

  group('canSendReport', () {
    test('a category alone is enough', () {
      expect(canSendReport(ReportReason.spam, ''), isTrue);
    });

    test('something else needs a note', () {
      expect(canSendReport(ReportReason.other, '   '), isFalse);
      expect(canSendReport(ReportReason.other, 'odd links'), isTrue);
    });

    test('nothing chosen cannot be sent', () {
      expect(canSendReport(null, 'a note'), isFalse);
    });
  });

  group('sending', () {
    late http.Request sent;

    Client clientAnswering(int status, Map<String, Object?> body) {
      final client = buildTestClient(
        userId: '@me:example.org',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode(body), status);
        }),
      )..homeserver = Uri.parse('https://example.org');
      client.bearerToken = 'token';
      return client;
    }

    test('a message report names the event and carries no content', () async {
      final client = clientAnswering(200, {});
      final room = buildTestRoom(client);
      final event = buildTestEvent(
        room,
        eventId: r'$bad',
        senderId: '@bob:example.org',
        content: {'msgtype': 'm.text', 'body': 'the private words'},
      );

      await reportMessage(event, ReportReason.harassment, note: 'threats');

      expect(
        sent.url.path,
        '/_matrix/client/v3/rooms/${Uri.encodeComponent(room.id)}'
        '/report/${Uri.encodeComponent(r'$bad')}',
      );
      expect(jsonDecode(sent.body), {'reason': 'harassment: threats'});
      expect(sent.body, isNot(contains('the private words')));
    });

    test('a person report goes to the user endpoint', () async {
      final client = clientAnswering(200, {});

      await reportPerson(
        client,
        '@bob:example.org',
        ReportReason.spam,
        roomId: '!room:example.org',
      );

      expect(
        sent.url.path,
        '/_matrix/client/v3/users/${Uri.encodeComponent('@bob:example.org')}'
        '/report',
      );
      expect(jsonDecode(sent.body), {
        'reason': 'spam (room !room:example.org)',
      });
    });

    test('a refused report throws', () async {
      final client = clientAnswering(429, {
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'Too many requests',
      });

      expect(
        reportPerson(client, '@bob:example.org', ReportReason.spam),
        throwsA(isA<MatrixException>()),
      );
    });
  });
}
