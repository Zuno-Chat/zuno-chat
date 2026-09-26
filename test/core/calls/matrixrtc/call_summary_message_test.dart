import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  test('displayBody for an ended call formats mm:ss', () {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'video',
      status: CallSummaryStatus.ended,
      durationMs: 92000,
    );
    expect(summary.displayBody, 'Video call · 1:32');
  });

  test('displayBody for a missed voice call', () {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    expect(summary.displayBody, 'Missed Voice call');
  });

  test('displayBody for a declined call', () {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'video',
      status: CallSummaryStatus.declined,
      durationMs: 0,
    );
    expect(summary.displayBody, 'Video call declined');
  });

  test('toJson/fromEvent round-trips through a real event', () {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.ended,
      durationMs: 5000,
    );
    final room = buildTestRoom(buildTestClient());
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: summary.toMessageContent(),
    );
    final parsed = CallSummary.fromEvent(event);
    expect(parsed?.callId, 'c1');
    expect(parsed?.status, CallSummaryStatus.ended);
    expect(parsed?.durationMs, 5000);
  });

  group('the relation that keeps a summary from pushing', () {
    CallSummary summary(CallSummaryStatus status) => CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: status,
      durationMs: 5000,
    );

    test('an answered call references the membership it came from', () {
      expect(
        summary(CallSummaryStatus.ended)
            .toMessageContent(membershipEventId: r'$m')['m.relates_to'],
        {'rel_type': 'm.reference', 'event_id': r'$m'},
      );
    });

    test('missed and declined calls stay pushed, since they alert or stop a '
        'ring on another device', () {
      for (final status in [
        CallSummaryStatus.missed,
        CallSummaryStatus.declined,
      ]) {
        expect(
          summary(status).toMessageContent(membershipEventId: r'$m'),
          isNot(contains('m.relates_to')),
        );
      }
    });

    test('without a membership there is nothing to reference', () {
      expect(
        summary(CallSummaryStatus.ended).toMessageContent(),
        isNot(contains('m.relates_to')),
      );
    });
  });

  test('fromEvent is null for an event with the wrong msgtype', () {
    final room = buildTestRoom(buildTestClient());
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: {'msgtype': 'm.text', 'body': 'not a call summary'},
    );
    expect(CallSummary.fromEvent(event), isNull);
  });

  test('fromEvent is null when a required field is missing', () {
    final room = buildTestRoom(buildTestClient());
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: {'msgtype': callSummaryMsgtype, 'call_id': 'c1'},
    );
    expect(CallSummary.fromEvent(event), isNull);
  });

  group('msgtype recognition', () {
    test('isCallSummaryMessage recognizes the current msgtype', () {
      expect(isCallSummaryMessage('im.zuno.call_summary'), isTrue);
      expect(isCallSummaryMessage('m.text'), isFalse);
      expect(isCallSummaryMessage(null), isFalse);
    });

    test('isCallInviteMessage recognizes the current msgtype', () {
      expect(isCallInviteMessage('im.zuno.call_invite'), isTrue);
      expect(isCallInviteMessage('im.zuno.call_decline'), isFalse);
    });

    test('isCallDeclineMessage recognizes the current msgtype', () {
      expect(isCallDeclineMessage('im.zuno.call_decline'), isTrue);
      expect(isCallDeclineMessage('im.zuno.call_invite'), isFalse);
    });

    test('isCallSignalingMessage covers invite and decline, not summary', () {
      expect(isCallSignalingMessage('im.zuno.call_invite'), isTrue);
      expect(isCallSignalingMessage('im.zuno.call_decline'), isTrue);
      expect(isCallSignalingMessage('im.zuno.call_summary'), isFalse);
      expect(isCallSignalingMessage('m.text'), isFalse);
    });
  });

  group('isMissedCallSummary', () {
    Event summaryEvent(CallSummaryStatus status) => buildTestEvent(
      buildTestRoom(buildTestClient()),
      eventId: r'$1',
      senderId: '@a:x',
      content: CallSummary(
        callId: 'c1',
        kind: 'video',
        status: status,
        durationMs: 204000,
      ).toMessageContent(),
    );

    test('is true only for a missed call', () {
      expect(
        isMissedCallSummary(summaryEvent(CallSummaryStatus.missed)),
        isTrue,
      );
      expect(
        isMissedCallSummary(summaryEvent(CallSummaryStatus.ended)),
        isFalse,
      );
      expect(
        isMissedCallSummary(summaryEvent(CallSummaryStatus.declined)),
        isFalse,
      );
    });

    test('is false for anything that is not a call summary at all', () {
      final event = buildTestEvent(
        buildTestRoom(buildTestClient()),
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': 'm.text', 'body': 'Video call · 3:24'},
      );
      expect(isMissedCallSummary(event), isFalse);
    });
  });
}
