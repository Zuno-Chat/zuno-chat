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

  test('starts with no corrections, so the raw server count shows through', () {
    expect(
      displayedUnreadCount(container.read(callUnreadCorrectionProvider), room),
      3,
    );
  });

  test('a hidden call-invite message adds one correction for its room', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$invite',
        senderId: '@a:x',
        content: {'msgtype': 'im.zuno.call_invite'},
      ),
    );
    await pumpEventQueue();
    final corrections = container.read(callUnreadCorrectionProvider);
    expect(displayedUnreadCount(corrections, room), 2);
  });

  test('an in-room verification message also corrects, being equally '
      'hidden from the timeline', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$verif',
        senderId: '@a:x',
        content: {'msgtype': 'm.key.verification.request'},
      ),
    );
    await pumpEventQueue();
    expect(
      displayedUnreadCount(container.read(callUnreadCorrectionProvider), room),
      2,
    );
  });

  test('an ordinary message corrects nothing', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$m',
        senderId: '@a:x',
        content: {'msgtype': 'm.text', 'body': 'hello'},
      ),
    );
    await pumpEventQueue();
    expect(
      displayedUnreadCount(container.read(callUnreadCorrectionProvider), room),
      3,
    );
  });

  test('an edit corrects nothing — the server never counted it', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$edit',
        senderId: '@a:x',
        content: {
          'msgtype': 'm.text',
          'body': '* fixed',
          'm.new_content': {'msgtype': 'm.text', 'body': 'fixed'},
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$orig'},
        },
      ),
    );
    await pumpEventQueue();
    expect(
      displayedUnreadCount(container.read(callUnreadCorrectionProvider), room),
      3,
    );
  });

  test(
    'an answered call summary adds a correction; a missed one does not',
    () async {
      const ended = CallSummary(
        callId: 'c1',
        kind: 'voice',
        status: CallSummaryStatus.ended,
        durationMs: 1000,
      );
      const missed = CallSummary(
        callId: 'c2',
        kind: 'voice',
        status: CallSummaryStatus.missed,
        durationMs: 0,
      );
      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$1',
          senderId: '@a:x',
          content: ended.toMessageContent(),
        ),
      );
      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$2',
          senderId: '@a:x',
          content: missed.toMessageContent(),
        ),
      );
      await pumpEventQueue();
      final corrections = container.read(callUnreadCorrectionProvider);
      expect(displayedUnreadCount(corrections, room), 2);
    },
  );

  test(
    'clearFor removes a room\'s correction (e.g. once it is opened)',
    () async {
      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$invite',
          senderId: '@a:x',
          content: {'msgtype': 'im.zuno.call_invite'},
        ),
      );
      await pumpEventQueue();
      container.read(callUnreadCorrectionProvider.notifier).clearFor(room.id);
      expect(
        displayedUnreadCount(
          container.read(callUnreadCorrectionProvider),
          room,
        ),
        3,
      );
    },
  );

  test('displayedUnreadCount never goes negative', () async {
    final emptyRoom = buildTestRoom(client, id: '!empty:x');
    client.onTimelineEvent.add(
      buildTestEvent(
        emptyRoom,
        eventId: r'$invite',
        senderId: '@a:x',
        content: {'msgtype': 'im.zuno.call_invite'},
      ),
    );
    await pumpEventQueue();
    final corrections = container.read(callUnreadCorrectionProvider);
    expect(displayedUnreadCount(corrections, emptyRoom), 0);
  });
}
