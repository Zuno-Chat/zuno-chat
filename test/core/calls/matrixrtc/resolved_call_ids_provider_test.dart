import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/recording_incoming_call_presenter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room room;
  late ProviderContainer container;
  late SharedPreferences prefs;
  late RecordingIncomingCallPresenter presenter;

  ProviderContainer containerWith() => ProviderContainer(
    overrides: [
      matrixClientProvider.overrideWithValue(client),
      sharedPreferencesProvider.overrideWithValue(prefs),
      incomingCallPresenterProvider.overrideWithValue(presenter),
    ],
  );

  setUp(() async {
    client = buildTestClient();
    room = buildTestRoom(client);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    presenter = RecordingIncomingCallPresenter();
    container = containerWith();
    addTearDown(container.dispose);
    container.read(resolvedCallIdsProvider);
  });

  test('starts empty', () {
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  test('a call summary marks its call_id resolved', () async {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: summary.toMessageContent(),
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('a call summary also cancels the ring notification', () async {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: summary.toMessageContent(),
      ),
    );
    await pumpEventQueue();
    expect(presenter.ends, hasLength(1));
  });

  test('other event types are ignored', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$invite',
        senderId: '@a:x',
        content: {'msgtype': 'im.zuno.call_invite', 'call_id': 'c1'},
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  test('a summary with no call_id is ignored rather than crashing', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': 'im.zuno.call_summary'},
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  test('multiple resolved calls accumulate', () async {
    for (final callId in ['c1', 'c2']) {
      const missed = CallSummaryStatus.missed;
      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: '\$$callId',
          senderId: '@a:x',
          content: CallSummary(
            callId: callId,
            kind: 'voice',
            status: missed,
            durationMs: 0,
          ).toMessageContent(),
        ),
      );
    }
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), {'c1', 'c2'});
  });

  test('markResolved adds a call_id without needing a summary event', () {
    container.read(resolvedCallIdsProvider.notifier).markResolved('c1');
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('markResolved is idempotent for a call_id already resolved', () async {
    const summary = CallSummary(
      callId: 'c1',
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    );
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: summary.toMessageContent(),
      ),
    );
    await pumpEventQueue();
    container.read(resolvedCallIdsProvider.notifier).markResolved('c1');
    expect(container.read(resolvedCallIdsProvider), {'c1'});
  });

  test('marking a call already resolved again changes nothing: no one is '
      'told and nothing is written', () async {
    final notifier = container.read(resolvedCallIdsProvider.notifier);
    notifier.markResolved('c1');
    await pumpEventQueue();
    await prefs.clear();
    final before = container.read(resolvedCallIdsProvider);
    var heard = 0;
    container.listen(resolvedCallIdsProvider, (_, _) => heard++);

    notifier.markResolved('c1');
    await pumpEventQueue();

    expect(heard, 0);
    expect(container.read(resolvedCallIdsProvider), same(before));
    expect(readResolvedCallIds(prefs), isEmpty);
  });

  test('seeds itself from a resolution stored by another isolate', () async {
    await markCallResolvedOnDisk(prefs, 'from-push');
    final seeded = containerWith();
    addTearDown(seeded.dispose);

    expect(seeded.read(resolvedCallIdsProvider), contains('from-push'));
  });

  test('markResolved persists for the other isolate to see', () async {
    container.read(resolvedCallIdsProvider.notifier).markResolved('c9');
    await Future<void>.delayed(Duration.zero);

    expect(readResolvedCallIds(prefs), contains('c9'));
  });

  group('one truth with the push path', () {
    test('a call the push path resolves in this isolate reaches the provider '
        'at once', () {
      unawaited(markCallResolved('from-push'));

      expect(container.read(resolvedCallIdsProvider), contains('from-push'));
    });

    test('a call another isolate resolved after the provider loaded is found '
        'on disk, and the provider learns it', () async {
      await markCallResolvedOnDisk(prefs, 'from-headless');
      expect(container.read(resolvedCallIdsProvider), isEmpty);

      expect(await isCallResolved('from-headless'), isTrue);
      expect(container.read(resolvedCallIdsProvider), {'from-headless'});
    });

    test('a call the provider resolved is resolved for the push path before '
        'its disk write lands', () async {
      container.read(resolvedCallIdsProvider.notifier).markResolved('c1');
      await prefs.clear();

      expect(await isCallResolved('c1'), isTrue);
    });

    test('once the provider is gone, a push-path mark goes to disk '
        'only', () async {
      container.dispose();

      await markCallResolved('after-dispose');

      await prefs.reload();
      expect(readResolvedCallIds(prefs), contains('after-dispose'));
    });
  });

  Future<void> summarize(
    Room inRoom,
    String callId, {
    CallSummaryStatus? status,
  }) async {
    client.onTimelineEvent.add(
      buildTestEvent(
        inRoom,
        eventId: '\$summary-$callId',
        senderId: '@a:x',
        content: status == null
            ? {'msgtype': callSummaryMsgtype, 'call_id': callId}
            : CallSummary(
                callId: callId,
                kind: 'voice',
                status: status,
                durationMs: 0,
              ).toMessageContent(),
      ),
    );
    await pumpEventQueue();
  }

  group('the ring a summary ends', () {
    test('a declined call ends it as declined elsewhere, naming its room and '
        'call', () async {
      await summarize(room, 'c1', status: CallSummaryStatus.declined);

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.declinedElsewhere),
      ]);
    });

    test('a missed or ended call ends it as cancelled by the caller', () async {
      await summarize(room, 'c1', status: CallSummaryStatus.missed);
      await summarize(room, 'c2', status: CallSummaryStatus.ended);

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.remoteEnded),
        (roomId: room.id, callId: 'c2', end: RingEnd.remoteEnded),
      ]);
    });

    test(
      'a summary with no status ends it as cancelled by the caller',
      () async {
        await summarize(room, 'c3');

        expect(presenter.ends, [
          (roomId: room.id, callId: 'c3', end: RingEnd.remoteEnded),
        ]);
        expect(container.read(resolvedCallIdsProvider), {'c3'});
      },
    );

    test('a summary in another room names that room', () async {
      final other = buildTestRoom(client, id: '!other:example.org');

      await summarize(other, 'c4', status: CallSummaryStatus.declined);

      expect(presenter.ends, [
        (
          roomId: '!other:example.org',
          callId: 'c4',
          end: RingEnd.declinedElsewhere,
        ),
      ]);
    });
  });

  group('through the platform presenter', () {
    late RecordedCallsChannel toNative;

    setUp(() {
      toNative = installFakeCallsChannel();
    });

    void resolveOn(PlatformCapabilities capabilities) {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ],
      );
      addTearDown(container.dispose);
      container.read(resolvedCallIdsProvider);
    }

    test('on iOS CallKit hears a declined call as declined elsewhere and a '
        'missed one as ended remotely', () async {
      resolveOn(iosCapabilities);

      await summarize(room, 'c1', status: CallSummaryStatus.declined);
      await summarize(room, 'c2', status: CallSummaryStatus.missed);

      expect(toNative.calls.map((c) => [c.method, c.arguments]), [
        [
          'endIncomingCall',
          {'roomId': room.id, 'callId': 'c1', 'reason': 'declinedElsewhere'},
        ],
        [
          'endIncomingCall',
          {'roomId': room.id, 'callId': 'c2', 'reason': 'remoteEnded'},
        ],
      ]);
    });

    test('on Android the ring notification still comes down and nothing '
        'reaches the calls channel', () async {
      installSilentNotificationSideChannels();
      final callStyle = installFakeCallStyleChannel();
      resolveOn(androidCapabilities);

      await summarize(room, 'c1', status: CallSummaryStatus.declined);

      expect(callStyle.calls.map((c) => c.method), ['cancelIncomingCallStyle']);
      expect(toNative.calls, isEmpty);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
    });

    Future<void> ringingOnAndroid(String callId) => saveRingingCall(prefs, (
      roomId: room.id,
      callId: callId,
      callerId: '@a:x',
      isVideo: false,
    ));

    Future<String?> rememberedCallId() async {
      await prefs.reload();
      return readRingingCall(prefs)?.callId;
    }

    void holdSystemRing(String callId) =>
        SystemRing.instance.set(roomId: room.id, callId: callId);

    test('on Android a summary for a call other than the one ringing leaves '
        'the ring notification up and remembered, yet resolves that other '
        'call', () async {
      installSilentNotificationSideChannels();
      final callStyle = installFakeCallStyleChannel();
      await ringingOnAndroid('c1');
      holdSystemRing('c1');
      resolveOn(androidCapabilities);
      final other = buildTestRoom(client, id: '!other:example.org');

      await summarize(other, 'c2', status: CallSummaryStatus.declined);

      expect(callStyle.calls, isEmpty);
      expect(await rememberedCallId(), 'c1');
      expect(SystemRing.instance.ringing.value?.callId, 'c1');
      expect(container.read(resolvedCallIdsProvider), {'c2'});
      expect(toNative.calls, isEmpty);
    });

    test('on Android a summary for the ringing call takes its notification '
        'down, forgets it and lets go of the ring, though no ring screen is '
        'up to do it', () async {
      installSilentNotificationSideChannels();
      final callStyle = installFakeCallStyleChannel();
      await ringingOnAndroid('c1');
      holdSystemRing('c1');
      resolveOn(androidCapabilities);

      await summarize(room, 'c1', status: CallSummaryStatus.missed);

      expect(callStyle.calls.map((c) => c.method), ['cancelIncomingCallStyle']);
      expect(await rememberedCallId(), isNull);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
      expect(toNative.calls, isEmpty);
    });
  });
}
