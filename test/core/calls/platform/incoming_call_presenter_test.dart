import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart'
    show RingingCallInfo;
import 'package:zuno/core/calls/notifications/ring_notification.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

void main() {
  late RecordedNotifications notifications;
  late RecordedCallStyleCalls callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
  });

  tearDown(() async {
    await pumpEventQueue();
    await NotificationSoundPlayer.instance.stopIncomingRing();
  });

  Future<RingOutcome> ring(IncomingCallPresenter presenter) =>
      presenter.showIncoming(
        callerName: 'Bob',
        callerId: '@bob:example.org',
        isVideo: true,
        roomId: '!room:example.org',
        callId: 'call1',
        isGroupCall: true,
        avatarBytes: Uint8List.fromList([1, 2, 3]),
      );

  Future<RingingCallInfo?> remembered() async =>
      readRingingCall(await SharedPreferences.getInstance());

  group('picking the presenter', () {
    test('android rings through its own full-screen notification', () {
      expect(
        incomingCallPresenterFor(androidCapabilities),
        isA<AndroidIncomingCallPresenter>(),
      );
    });

    test('ios rings through CallKit', () {
      expect(
        incomingCallPresenterFor(iosCapabilities),
        isA<CallKitIncomingCallPresenter>(),
      );
    });

    test('without a native ring screen there is nothing to present with', () {
      expect(
        incomingCallPresenterFor(
          capabilitiesLike(androidCapabilities, nativeIncomingRingUi: false),
        ),
        isA<NoopIncomingCallPresenter>(),
      );
    });

    test('the full-screen permission no longer picks the presenter', () {
      expect(
        incomingCallPresenterFor(
          capabilitiesLike(androidCapabilities, fullScreenIntent: false),
        ),
        isA<AndroidIncomingCallPresenter>(),
      );
    });

    test('the provider follows the platform capabilities', () {
      final android = ProviderContainer();
      addTearDown(android.dispose);
      final ios = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(iosCapabilities),
        ],
      );
      addTearDown(ios.dispose);

      expect(
        android.read(incomingCallPresenterProvider),
        isA<AndroidIncomingCallPresenter>(),
      );
      expect(
        ios.read(incomingCallPresenterProvider),
        isA<CallKitIncomingCallPresenter>(),
      );
    });
  });

  group('the android presenter', () {
    const presenter = AndroidIncomingCallPresenter();

    test('posts the call-style ring with everything its actions need, and '
        'remembers the call', () async {
      await ring(presenter);

      expect((callStyle.lastShow.arguments as Map).cast<String, Object?>(), {
        'channelId': 'calls_ringing_group',
        'title': 'Incoming video call',
        'callerName': 'Bob',
        'callerId': '@bob:example.org',
        'isVideo': true,
        'roomId': '!room:example.org',
        'callId': 'call1',
        'avatarBytes': Uint8List.fromList([1, 2, 3]),
      });
      expect((await remembered())?.callId, 'call1');
    });

    test('reports the ring only while its notification is on screen', () async {
      await ring(presenter);

      notifications.active = [ringNotificationOnScreen()];
      expect((await presenter.activeRing())?.callId, 'call1');

      notifications.active = const [];
      expect(await presenter.activeRing(), isNull);
    });

    test(
      'cancelling takes the notification down and forgets the call',
      () async {
        await ring(presenter);

        await presenter.cancelIncoming();
        notifications.active = [ringNotificationOnScreen()];

        expect(callStyle.calls.map((c) => c.method), [
          'showIncomingCallStyle',
          'cancelIncomingCallStyle',
        ]);
        expect(await remembered(), isNull);
        expect(await presenter.activeRing(), isNull);
      },
    );

    test('cancelling another call leaves this ring\'s notification up, still '
        'remembered and reported', () async {
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call2',
        end: RingEnd.declinedElsewhere,
      );
      notifications.active = [ringNotificationOnScreen()];

      expect(callStyle.calls.map((c) => c.method), ['showIncomingCallStyle']);
      expect((await remembered())?.callId, 'call1');
      expect((await presenter.activeRing())?.callId, 'call1');
    });

    test('cancelling the ringing call lets go of the ring it holds, and '
        'cancelling another call keeps it', () async {
      await ring(presenter);
      SystemRing.instance.set(roomId: '!room:example.org', callId: 'call1');

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call2',
      );
      expect(SystemRing.instance.ringing.value?.callId, 'call1');

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );
      expect(SystemRing.instance.ringing.value, isNull);
    });

    test('rings a group call under the caller\'s name, as before, and never '
        'asks CallKit', () async {
      final native = installFakeCallsChannel();

      final outcome = await presenter.showIncoming(
        callerName: 'Bob',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: 'call1',
        isGroupCall: true,
        roomName: 'Weekend hike',
      );
      expect(SystemRing.instance.ringing.value, isNull);
      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
        end: RingEnd.answeredElsewhere,
      );

      expect(outcome, RingOutcome.shown);
      expect((callStyle.lastShow.arguments as Map).cast<String, Object?>(), {
        'channelId': 'calls_ringing_group',
        'title': 'Incoming voice call',
        'callerName': 'Bob',
        'callerId': '@bob:example.org',
        'isVideo': false,
        'roomId': '!room:example.org',
        'callId': 'call1',
        'avatarBytes': null,
      });
      expect(callStyle.calls.map((c) => c.method), [
        'showIncomingCallStyle',
        'cancelIncomingCallStyle',
      ]);
      expect(native.methods, isNot(contains('reportIncomingCall')));
      expect(native.methods, isNot(contains('endIncomingCall')));
    });
  });

  group('every presenter that really rings', () {
    test('remembers the call before presenting it, so a cold start can reopen '
        'it, even when presenting fails', () async {
      final presenter = _FakeRememberingPresenter(fails: true);

      await expectLater(ring(presenter), throwsA(isA<StateError>()));

      expect((await remembered())?.callId, 'call1');
      expect((await remembered())?.isVideo, isTrue);
    });

    test('forgets the call when the ring is cancelled', () async {
      final presenter = _FakeRememberingPresenter();
      await ring(presenter);

      await presenter.cancelIncoming();

      expect(await remembered(), isNull);
      expect(presenter.dismissed, 1);
    });

    test('cancelling another call leaves the remembered ring up and dismisses '
        'nothing', () async {
      final presenter = _FakeRememberingPresenter();
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call2',
        end: RingEnd.declinedElsewhere,
      );

      expect((await remembered())?.callId, 'call1');
      expect(presenter.dismissed, 0);
    });

    test('cancelling the ringing call by name dismisses it and forgets '
        'it', () async {
      final presenter = _FakeRememberingPresenter();
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
        end: RingEnd.remoteEnded,
      );

      expect(await remembered(), isNull);
      expect(presenter.dismissed, 1);
    });

    test('a cancel that names only the room takes down whatever '
        'rings', () async {
      final presenter = _FakeRememberingPresenter();
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        end: RingEnd.unanswered,
      );

      expect(await remembered(), isNull);
      expect(presenter.dismissed, 1);
    });

    test('a remembered ring of another call too old to still be ringing does '
        'not hold the cancel back, and is forgotten', () async {
      final presenter = _FakeRememberingPresenter();
      final prefs = await SharedPreferences.getInstance();
      await saveRingingCall(prefs, (
        roomId: '!room:example.org',
        callId: 'call1',
        callerId: '@bob:example.org',
        isVideo: true,
      ), now: DateTime.now().subtract(const Duration(seconds: 46)));

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call2',
        end: RingEnd.remoteEnded,
      );

      expect(ringAgeFor(prefs, 'call1'), isNull);
      expect(presenter.dismissed, 1);
    });

    test('with nothing remembered, a cancel naming a call still '
        'dismisses', () async {
      final presenter = _FakeRememberingPresenter();

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
        end: RingEnd.remoteEnded,
      );

      expect(await remembered(), isNull);
      expect(presenter.dismissed, 1);
    });
  });

  group('the presenter for a platform with neither a ring screen nor '
      'CallKit', () {
    final presenter = incomingCallPresenterFor(
      capabilitiesLike(androidCapabilities, nativeIncomingRingUi: false),
    );

    test(
      'posts nothing, rings nothing, remembers nothing, reports no ring, and '
      'tells its caller the ring could not be shown',
      () async {
        expect(await ring(presenter), RingOutcome.unavailable);
        await pumpEventQueue();
        notifications.active = [ringNotificationOnScreen()];

        expect(await presenter.activeRing(), isNull);
        await presenter.cancelIncoming();

        expect(callStyle.calls, isEmpty);
        expect(notifications.methods, isEmpty);
        expect(NotificationSoundPlayer.instance.ownsIncomingRing, isFalse);
        expect(await remembered(), isNull);
      },
    );

    test('an incoming call handed to it goes nowhere', () async {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));

      final outcome = await postRingNotification(
        IncomingCall(
          room: room,
          callId: 'call1',
          callerId: '@bob:example.org',
          kind: CallKind.voice,
        ),
        presenter: presenter,
      );

      expect(outcome, RingOutcome.unavailable);
      expect(callStyle.calls, isEmpty);
      expect(await remembered(), isNull);
    });
  });

  group('the CallKit presenter', () {
    const presenter = CallKitIncomingCallPresenter();
    const roomId = '!room:example.org';
    const ringing = (roomId: roomId, callId: 'call1');
    late TestDefaultBinaryMessenger messenger;
    late RecordedCallsChannel native;
    late Future<Object?> Function() report;

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      report = () async => 'shown';
      native = installFakeCallsChannel(
        reply: (call) => call.method == 'reportIncomingCall' ? report() : null,
      );
    });

    Future<RingOutcome> ringFor({
      String callId = 'call1',
      bool isVideo = false,
      bool isGroupCall = false,
      String? roomName = 'Weekend hike',
    }) => presenter.showIncoming(
      callerName: 'Bob',
      callerId: '@bob:example.org',
      isVideo: isVideo,
      roomId: roomId,
      callId: callId,
      isGroupCall: isGroupCall,
      roomName: roomName,
      avatarBytes: Uint8List.fromList([1, 2, 3]),
    );

    List<Object?> sent() => [
      for (final call in native.calls) [call.method, call.arguments],
    ];

    Map<String, Object?> reported({
      required String name,
      bool isVideo = false,
    }) => {
      'roomId': roomId,
      'callId': 'call1',
      'callerId': '@bob:example.org',
      'name': name,
      'isVideo': isVideo,
    };

    Map<String, Object?> ended(String reason) => {
      'roomId': roomId,
      'callId': 'call1',
      'reason': reason,
    };

    test(
      'reports a one-to-one call to CallKit under the caller\'s name',
      () async {
        expect(await ringFor(), RingOutcome.shown);

        expect(sent(), [
          ['reportIncomingCall', reported(name: 'Bob')],
        ]);
      },
    );

    test('reports a group call under the room\'s name', () async {
      await ringFor(isGroupCall: true, isVideo: true);

      expect(sent(), [
        ['reportIncomingCall', reported(name: 'Weekend hike', isVideo: true)],
      ]);
    });

    test('reports a group call without a room name under the caller\'s '
        'name', () async {
      await ringFor(isGroupCall: true, roomName: null);

      expect(sent(), [
        ['reportIncomingCall', reported(name: 'Bob')],
      ]);
    });

    test('turns CallKit\'s answer into the ring outcome', () async {
      const outcomes = {
        'shown': RingOutcome.shown,
        'filtered': RingOutcome.filtered,
        'unavailable': RingOutcome.unavailable,
        'something newer': RingOutcome.unavailable,
        null: RingOutcome.unavailable,
      };

      for (final MapEntry(key: answer, value: outcome) in outcomes.entries) {
        report = () async => answer;
        expect(await ringFor(), outcome, reason: '$answer');
      }
    });

    test(
      'a failing or missing CallKit side makes the ring unavailable',
      () async {
        report = () async => throw PlatformException(code: 'callkit');
        expect(await ringFor(), RingOutcome.unavailable);

        messenger.setMockMethodCallHandler(_callsChannel, null);
        expect(await ringFor(), RingOutcome.unavailable);
      },
    );

    test('marks the call as ringing before CallKit is asked, and keeps the '
        'mark while CallKit shows the ring', () async {
      SystemRingingCall? markWhileAsked;
      report = () async {
        markWhileAsked = SystemRing.instance.ringing.value;
        return 'shown';
      };

      await ringFor();

      expect(markWhileAsked, ringing);
      expect(SystemRing.instance.ringing.value, ringing);
    });

    test('a ring CallKit does not show leaves no call marked as '
        'ringing', () async {
      final marks = <SystemRingingCall?>[];
      void mark() => marks.add(SystemRing.instance.ringing.value);
      SystemRing.instance.ringing.addListener(mark);
      addTearDown(() => SystemRing.instance.ringing.removeListener(mark));

      for (final answer in <Future<Object?> Function()>[
        () async => 'filtered',
        () async => 'unavailable',
        () async => throw PlatformException(code: 'callkit'),
      ]) {
        report = answer;
        await ringFor();
      }
      messenger.setMockMethodCallHandler(_callsChannel, null);
      await ringFor();

      expect(marks, [
        for (var i = 0; i < 4; i++) ...[ringing, null],
      ]);
    });

    test('a cancel that lands while CallKit is still being asked leaves no '
        'call marked as ringing, whatever CallKit answers', () async {
      for (final answer in ['shown', 'filtered']) {
        native.clear();
        final asked = Completer<Object?>();
        report = () => asked.future;

        final outcome = ringFor();
        expect(SystemRing.instance.ringing.value, ringing);
        await presenter.cancelIncoming(
          roomId: roomId,
          callId: 'call1',
          end: RingEnd.remoteEnded,
        );
        asked.complete(answer);
        await outcome;

        expect(SystemRing.instance.ringing.value, isNull, reason: answer);
        expect(sent(), [
          ['reportIncomingCall', reported(name: 'Bob')],
          ['endIncomingCall', ended('remoteEnded')],
        ]);
      }
    });

    test('the ringing mark lapses on its own after its lifetime', () {
      fakeAsync((async) {
        unawaited(ringFor());
        async.flushMicrotasks();

        async.elapse(SystemRing.lifetime - const Duration(seconds: 1));
        expect(SystemRing.instance.ringing.value, ringing);

        async.elapse(const Duration(seconds: 1));
        expect(SystemRing.instance.ringing.value, isNull);
      });
    });

    test('an earlier ring lapsing never clears a later one', () {
      fakeAsync((async) {
        unawaited(ringFor(callId: 'call1'));
        async.elapse(const Duration(seconds: 50));
        unawaited(ringFor(callId: 'call2'));

        async.elapse(const Duration(seconds: 50));
        expect(SystemRing.instance.ringing.value?.callId, 'call2');

        async.elapse(const Duration(seconds: 10));
        expect(SystemRing.instance.ringing.value, isNull);
      });
    });

    test('ending the ring tells CallKit why', () async {
      const reasons = {
        RingEnd.remoteEnded: 'remoteEnded',
        RingEnd.answeredElsewhere: 'answeredElsewhere',
        RingEnd.declinedElsewhere: 'declinedElsewhere',
        RingEnd.unanswered: 'unanswered',
      };

      for (final end in RingEnd.values) {
        await presenter.cancelIncoming(
          roomId: roomId,
          callId: 'call1',
          end: end,
        );
      }

      expect(sent(), [
        for (final end in RingEnd.values)
          ['endIncomingCall', ended(reasons[end]!)],
      ]);
    });

    test('a cancel with no reason tells CallKit the other side ended the '
        'call', () async {
      await presenter.cancelIncoming(roomId: roomId, callId: 'call1');

      expect(sent(), [
        ['endIncomingCall', ended('remoteEnded')],
      ]);
    });

    test('ending a ring clears its own mark, never another call\'s', () async {
      await ringFor();

      await presenter.cancelIncoming(
        roomId: roomId,
        callId: 'call2',
        end: RingEnd.answeredElsewhere,
      );
      expect(SystemRing.instance.ringing.value, ringing);

      await presenter.cancelIncoming(
        roomId: roomId,
        callId: 'call1',
        end: RingEnd.answeredElsewhere,
      );
      expect(SystemRing.instance.ringing.value, isNull);
    });

    test('a cancel that cannot name the call leaves CallKit and the ringing '
        'mark alone', () async {
      await ringFor();
      native.clear();

      await presenter.cancelIncoming();
      await presenter.cancelIncoming(roomId: roomId, end: RingEnd.unanswered);
      await presenter.cancelIncoming(callId: 'call1', end: RingEnd.unanswered);

      expect(native.calls, isEmpty);
      expect(SystemRing.instance.ringing.value, ringing);
    });

    test('a cancel without a platform side is not an error', () async {
      await ringFor();
      messenger.setMockMethodCallHandler(_callsChannel, null);

      await expectLater(
        presenter.cancelIncoming(
          roomId: roomId,
          callId: 'call1',
          end: RingEnd.unanswered,
        ),
        completes,
      );
      expect(SystemRing.instance.ringing.value, isNull);
    });

    test('rings through CallKit alone: no notification, no ringtone of its '
        'own, nothing remembered', () async {
      await ringFor(isGroupCall: true);
      await pumpEventQueue();

      expect(callStyle.calls, isEmpty);
      expect(notifications.methods, isEmpty);
      expect(NotificationSoundPlayer.instance.ownsIncomingRing, isFalse);
      expect(await remembered(), isNull);
    });

    test('leaves the ring on screen to CallKit and reports none of its '
        'own', () async {
      await ringFor();

      expect(await presenter.activeRing(), isNull);
    });
  });
}

class _FakeRememberingPresenter extends RememberingIncomingCallPresenter {
  _FakeRememberingPresenter({this.fails = false});

  final bool fails;
  int dismissed = 0;

  @override
  Future<void> presentIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    required bool isGroupCall,
    Uint8List? avatarBytes,
  }) async {
    if (fails) throw StateError('no ring screen');
  }

  @override
  Future<void> dismissIncoming() async => dismissed++;

  @override
  Future<RingingCallInfo?> activeRing() => rememberedRing();
}
