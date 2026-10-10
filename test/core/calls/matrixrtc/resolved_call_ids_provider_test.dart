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
import '../../../helpers/native_method_calls.dart';
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

  test(
    'call summaries mark their calls resolved, and they accumulate',
    () async {
      await summarize(room, 'c1', status: CallSummaryStatus.missed);
      await summarize(room, 'c2', status: CallSummaryStatus.ended);

      expect(container.read(resolvedCallIdsProvider), {'c1', 'c2'});
    },
  );

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
    expect(presenter.ends, isEmpty);
  });

  test('a summary with no call_id is ignored rather than crashing', () async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': callSummaryMsgtype},
      ),
    );
    await pumpEventQueue();
    expect(container.read(resolvedCallIdsProvider), isEmpty);
    expect(presenter.ends, isEmpty);
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

  test('markResolved adds a call at once, without a summary event, and '
      'persists it for the other isolate to see', () async {
    container.read(resolvedCallIdsProvider.notifier).markResolved('c9');
    expect(container.read(resolvedCallIdsProvider), {'c9'});

    await pumpEventQueue();

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
    late RecordedMethodCalls toNative;

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

    test('on Android a summary for the ringing call takes its notification '
        'down, forgets it and lets go of the ring, though no ring screen is '
        'up to do it', () async {
      installSilentNotificationSideChannels();
      final callStyle = installFakeCallStyleChannel();
      await saveRingingCall(prefs, (
        roomId: room.id,
        callId: 'c1',
        callerId: '@a:x',
        isVideo: false,
      ));
      SystemRing.instance.set(roomId: room.id, callId: 'c1');
      resolveOn(androidCapabilities);

      await summarize(room, 'c1', status: CallSummaryStatus.missed);

      expect(callStyle.calls.map((c) => c.method), ['cancelIncomingCallStyle']);
      await prefs.reload();
      expect(readRingingCall(prefs), isNull);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
      expect(toNative.calls, isEmpty);
    });
  });
}
