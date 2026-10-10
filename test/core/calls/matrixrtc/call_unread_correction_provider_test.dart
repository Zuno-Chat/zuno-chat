import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/call_unread_correction_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  late ProviderContainer container;

  setUp(() {
    client = buildTestClient();
    room = buildTestRoom(client, notificationCount: 3);
    container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    container.read(callUnreadCorrectionProvider);
  });

  var events = 0;

  Future<void> receive(Map<String, Object?> content, {Room? inRoom}) async {
    client.onTimelineEvent.add(
      buildTestEvent(
        inRoom ?? room,
        eventId: '\$event-${events++}',
        senderId: '@a:x',
        content: content,
      ),
    );
    await pumpEventQueue();
  }

  int shown([Room? inRoom]) => displayedUnreadCount(
    container.read(callUnreadCorrectionProvider),
    inRoom ?? room,
  );

  test(
    'a hidden call-invite message adds one correction for its room',
    () async {
      await receive({'msgtype': callInviteMsgtype});

      expect(shown(), 2);
    },
  );

  test('an in-room verification message also corrects, being equally '
      'hidden from the timeline', () async {
    await receive({'msgtype': 'm.key.verification.request'});

    expect(shown(), 2);
  });

  test('an ordinary message corrects nothing, so the raw server count shows '
      'through', () async {
    await receive({'msgtype': 'm.text', 'body': 'hello'});

    expect(shown(), 3);
  });

  test('an edit corrects nothing — the server never counted it', () async {
    await receive({
      'msgtype': 'm.text',
      'body': '* fixed',
      'm.new_content': {'msgtype': 'm.text', 'body': 'fixed'},
      'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$orig'},
    });

    expect(shown(), 3);
  });

  test(
    'an answered call summary adds a correction; a missed one does not',
    () async {
      await receive(
        const CallSummary(
          callId: 'c1',
          kind: 'voice',
          status: CallSummaryStatus.ended,
          durationMs: 1000,
        ).toMessageContent(),
      );
      await receive(
        const CallSummary(
          callId: 'c2',
          kind: 'voice',
          status: CallSummaryStatus.missed,
          durationMs: 0,
        ).toMessageContent(),
      );

      expect(shown(), 2);
    },
  );

  test('call events that reference the call correct nothing — the server '
      'never counted them', () async {
    await receive({
      'msgtype': callDeclineMsgtype,
      'call_id': 'c1',
      'm.relates_to': {'rel_type': 'm.reference', 'event_id': r'$member'},
    });
    await receive(
      const CallSummary(
        callId: 'c1',
        kind: 'voice',
        status: CallSummaryStatus.ended,
        durationMs: 1000,
      ).toMessageContent(membershipEventId: r'$member'),
    );

    expect(shown(), 3);
  });

  test(
    'clearFor removes a room\'s correction (e.g. once it is opened)',
    () async {
      await receive({'msgtype': callInviteMsgtype});

      container.read(callUnreadCorrectionProvider.notifier).clearFor(room.id);

      expect(shown(), 3);
    },
  );

  test('displayedUnreadCount never goes negative', () async {
    final emptyRoom = buildTestRoom(client, id: '!empty:x');

    await receive({'msgtype': callInviteMsgtype}, inRoom: emptyRoom);

    expect(shown(emptyRoom), 0);
  });
}
