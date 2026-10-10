import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/features/chat/presentation/not_sent.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:x');
    room = buildTestRoom(client);
  });

  Event message(
    EventStatus status, {
    String senderId = '@me:x',
    String id = r'$1',
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: senderId,
    status: status,
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
  );

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
      'copy would describe a call that is over', () {
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
      expect(notSentOwnEvents([failed]), isEmpty, reason: msgtype);
    }
  });

  test('notSentOwnEvents keeps only own failed events, in timeline order', () {
    final failedA = message(EventStatus.error, id: r'$a');
    final failedB = message(EventStatus.error, id: r'$b');

    final selected = notSentOwnEvents([
      message(EventStatus.sent, id: r'$sent'),
      failedA,
      message(EventStatus.error, senderId: '@a:x', id: r'$theirs'),
      message(EventStatus.sending, id: r'$pending'),
      failedB,
    ]);

    expect(selected, [failedA, failedB]);
  });
}
