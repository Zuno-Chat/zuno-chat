import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/l10n/l10n.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  CallSummary summaryOf(
    String kind,
    CallSummaryStatus status, {
    int durationMs = 0,
  }) => CallSummary(
    callId: 'c1',
    kind: kind,
    status: status,
    durationMs: durationMs,
  );

  group('displayBody', () {
    String bodyOf(
      String kind,
      CallSummaryStatus status, {
      int durationMs = 0,
    }) => summaryOf(kind, status, durationMs: durationMs).displayBody;

    test('an ended call shows its length as m:ss', () {
      expect(
        bodyOf('video', CallSummaryStatus.ended, durationMs: 92000),
        'Video call · 1:32',
      );
    });

    test('a missed voice call', () {
      expect(bodyOf('voice', CallSummaryStatus.missed), 'Missed Voice call');
    });

    test('a declined call', () {
      expect(
        bodyOf('video', CallSummaryStatus.declined),
        'Video call declined',
      );
    });
  });

  group('localizedBody', () {
    test('reads the same English as the body sent to the room', () {
      for (final kind in ['video', 'voice']) {
        for (final status in CallSummaryStatus.values) {
          final summary = summaryOf(kind, status, durationMs: 92000);
          expect(
            summary.localizedBody(englishLocalizations),
            summary.displayBody,
          );
        }
      }
    });

    test('names the kind of call', () {
      final video = summaryOf('video', CallSummaryStatus.ended);
      final voice = summaryOf('voice', CallSummaryStatus.ended);
      expect(video.localizedLabel(englishLocalizations), 'Video call');
      expect(voice.localizedLabel(englishLocalizations), 'Voice call');
    });
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
      content: {'msgtype': 'm.text', 'body': 'Video call · 3:24'},
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

  test('isCallSignalingMessage covers invite and decline, not summary', () {
    expect(isCallSignalingMessage('im.zuno.call_invite'), isTrue);
    expect(isCallSignalingMessage('im.zuno.call_decline'), isTrue);
    expect(isCallSignalingMessage('im.zuno.call_summary'), isFalse);
    expect(isCallSignalingMessage('m.text'), isFalse);
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
  });
}
