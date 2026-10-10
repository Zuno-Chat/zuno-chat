import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  late RecordedNotifications notifications;
  late RecordedMethodCalls callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
  });

  tearDown(pumpEventQueue);

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
    final cases = {
      'android rings through its own full-screen notification': (
        androidCapabilities,
        AndroidIncomingCallPresenter,
      ),
      'ios rings through CallKit': (
        iosCapabilities,
        CallKitIncomingCallPresenter,
      ),
      'without a native ring screen there is nothing to present with': (
        capabilitiesLike(androidCapabilities, nativeIncomingRingUi: false),
        NoopIncomingCallPresenter,
      ),
      'the full-screen permission no longer picks the presenter': (
        capabilitiesLike(androidCapabilities, fullScreenIntent: false),
        AndroidIncomingCallPresenter,
      ),
    };

    for (final MapEntry(key: name, value: (capabilities, presenter))
        in cases.entries) {
      test(name, () {
        final container = ProviderContainer(
          overrides: [
            platformCapabilitiesProvider.overrideWithValue(capabilities),
          ],
        );
        addTearDown(container.dispose);

        expect(
          container.read(incomingCallPresenterProvider).runtimeType,
          presenter,
        );
      });
    }
  });

  group('the android presenter', () {
    const presenter = AndroidIncomingCallPresenter();

    test('posts the call-style ring with everything its actions and its '
        'sound need, and remembers the call', () async {
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
        'ringtone': true,
        'ringtoneAsset': 'assets/sounds/ringtone.wav',
        'vibrate': true,
        'vibrationPattern': [0, 800, 500, 800, 2000],
      });
      expect((await remembered())?.callId, 'call1');
    });

    test('rings on the direct channel by default, the group channel for a '
        'group call', () async {
      Future<Object?> channelOf({
        required String callId,
        bool isGroupCall = false,
      }) async {
        await presenter.showIncoming(
          callerName: 'Bob',
          callerId: '@bob:example.org',
          isVideo: false,
          roomId: '!room:example.org',
          callId: callId,
          isGroupCall: isGroupCall,
        );
        return (callStyle.lastShow.arguments as Map)['channelId'];
      }

      expect(await channelOf(callId: 'call1'), 'calls_ringing');
      expect(
        await channelOf(callId: 'call2', isGroupCall: true),
        'calls_ringing_group',
      );
    });

    test('rings and buzzes exactly as the Ringtone and Vibrate for calls '
        'settings say', () async {
      const cases = {
        (ringtone: true, vibration: false): (ringtone: true, vibrate: false),
        (ringtone: false, vibration: true): (ringtone: false, vibrate: true),
        (ringtone: false, vibration: false): (ringtone: false, vibrate: false),
      };

      for (final MapEntry(key: settings, value: asked) in cases.entries) {
        SharedPreferences.setMockInitialValues({
          ringtoneEnabledKey: settings.ringtone,
          callVibrationEnabledKey: settings.vibration,
        });
        RememberingIncomingCallPresenter.forgetForTest();

        await ring(presenter);

        final args = callStyle.lastShow.arguments as Map;
        expect(
          (ringtone: args['ringtone'], vibrate: args['vibrate']),
          asked,
          reason: '$settings',
        );
      }
    });

    test('asks for no buzz on a platform without vibration patterns', () async {
      ambientCapabilities = capabilitiesLike(
        androidCapabilities,
        vibrationPatterns: false,
      );

      await ring(presenter);

      expect((callStyle.lastShow.arguments as Map)['vibrate'], isFalse);
    });

    test('plays a ringtone that ships with the app', () async {
      await ring(presenter);

      final asset =
          (callStyle.lastShow.arguments as Map)['ringtoneAsset'] as String;
      expect((await rootBundle.load(asset)).lengthInBytes, greaterThan(0));
    });

    test('leaves the sound to the native side, so no engine going away can '
        'cut it short', () async {
      final dartSound = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in const [
        'zuno/vibration',
        'xyz.luan/audioplayers',
        'xyz.luan/audioplayers.global',
      ]) {
        final channel = MethodChannel(name);
        messenger.setMockMethodCallHandler(channel, (call) async {
          dartSound.add('$name ${call.method}');
          return call.method == 'hasVibrator' ? true : null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }

      await ring(presenter);
      await pumpEventQueue();
      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );
      await pumpEventQueue();

      expect(dartSound, isEmpty);
    });

    test('takes the ring down through the native side, naming the call it '
        'means', () async {
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );
      await presenter.cancelIncoming();

      expect(
        callStyle.calls
            .where((c) => c.method == 'cancelIncomingCallStyle')
            .map((c) => c.arguments),
        [
          {'callId': 'call1'},
          {'callId': null},
        ],
      );
    });

    test('leaves forgetting the ring to the native side, which checks and '
        'forgets it in one step', () async {
      for (final answer in [true, false]) {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('zuno/call_style'),
          (call) async =>
              call.method == 'cancelIncomingCallStyle' ? answer : null,
        );
        RememberingIncomingCallPresenter.forgetForTest();
        await ring(presenter);

        await presenter.cancelIncoming(
          roomId: '!room:example.org',
          callId: 'call1',
        );

        expect((await remembered())?.callId, 'call1', reason: '$answer');
      }
    });

    test('without the native side, still forgets the ring itself', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('zuno/call_style'),
            null,
          );
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );

      expect(await remembered(), isNull);
    });

    test('reports the ring only while its notification is on screen', () async {
      await ring(presenter);

      notifications.active = [
        {...ringNotificationOnScreen(), 'id': 12345},
      ];
      expect(await presenter.activeRing(), isNull);

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
        'ringtone': true,
        'ringtoneAsset': 'assets/sounds/ringtone.wav',
        'vibrate': true,
        'vibrationPattern': [0, 800, 500, 800, 2000],
      });
      expect(callStyle.calls.map((c) => c.method), [
        'showIncomingCallStyle',
        'cancelIncomingCallStyle',
      ]);
      expect(native.methods, isNot(contains('reportIncomingCall')));
      expect(native.methods, isNot(contains('endIncomingCall')));
    });
  });

  group('a call that already rings', () {
    const presenter = AndroidIncomingCallPresenter();

    Iterable<MethodCall> posts() =>
        callStyle.calls.where((c) => c.method == 'showIncomingCallStyle');

    test('is not posted again, so its ring is not restarted and nothing takes '
        'it down', () async {
      await ring(presenter);

      expect(await ring(presenter), RingOutcome.shown);
      await pumpEventQueue();

      expect(callStyle.calls.map((c) => c.method), ['showIncomingCallStyle']);
    });

    test('presented twice at once is posted once', () async {
      await Future.wait([ring(presenter), ring(presenter)]);

      expect(posts(), hasLength(1));
    });

    test('rung by another isolate is not rung again here', () async {
      await saveRingingCall(await SharedPreferences.getInstance(), (
        roomId: '!room:example.org',
        callId: 'call1',
        callerId: '@bob:example.org',
        isVideo: true,
      ));
      notifications.active = [ringNotificationOnScreen()];

      expect(await ring(presenter), RingOutcome.shown);

      expect(posts(), isEmpty);
    });

    test('rings again once its ring was cancelled', () async {
      await ring(presenter);
      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );

      await ring(presenter);

      expect(posts(), hasLength(2));
    });

    test('does not stop a different call from ringing as before', () async {
      await ring(presenter);

      await presenter.showIncoming(
        callerName: 'Carol',
        callerId: '@carol:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: 'call2',
      );

      expect(posts().map((c) => (c.arguments as Map)['callId']), [
        'call1',
        'call2',
      ]);
    });

    test('a cancel that lands while the call is still being presented takes '
        'it down once it is up', () async {
      final presenting = Completer<void>();
      final slow = _FakeRememberingPresenter(presenting: presenting.future);

      final shown = ring(slow);
      await pumpEventQueue();
      final cancelled = slow.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );
      await pumpEventQueue();
      expect(slow.dismissals, isEmpty);

      presenting.complete();
      await Future.wait([shown, cancelled]);

      expect(slow.presented, 1);
      expect(slow.dismissals, ['call1']);
      expect(await remembered(), isNull);
    });
  });

  test('presenting a ring takes the app\'s decline route back', () async {
    await CallNotificationService.instance.initialize();
    final stranger = ReceivePort();
    addTearDown(stranger.close);
    IsolateNameServer.removePortNameMapping(declinePortName);
    IsolateNameServer.registerPortWithName(stranger.sendPort, declinePortName);

    await ring(const AndroidIncomingCallPresenter());

    expect(CallNotificationService.instance.stillHoldsDeclinePort(), isTrue);
  });

  group('every presenter that really rings', () {
    test('remembers the call before presenting it, so a cold start can reopen '
        'it, even when presenting fails', () async {
      final presenter = _FakeRememberingPresenter(fails: true);

      await expectLater(ring(presenter), throwsA(isA<StateError>()));

      expect((await remembered())?.callId, 'call1');
      expect((await remembered())?.isVideo, isTrue);
    });

    test('a cancel naming no call, even one naming the room, hands the whole '
        'ring over to be forgotten and taken down', () async {
      final presenter = _FakeRememberingPresenter();

      for (final roomId in [null, '!room:example.org']) {
        await ring(presenter);
        await presenter.cancelIncoming(roomId: roomId, end: RingEnd.unanswered);
        expect(await remembered(), isNull, reason: '$roomId');
      }

      expect(presenter.dismissals, [null, null]);
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
      expect(presenter.dismissals, isEmpty);
    });

    test('cancelling the ringing call by name hands that call over to be '
        'forgotten and taken down', () async {
      final presenter = _FakeRememberingPresenter();
      await ring(presenter);

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
        end: RingEnd.remoteEnded,
      );

      expect(presenter.dismissals, ['call1']);
      expect(await remembered(), isNull);
    });

    test('a remembered ring of another call too old to still be ringing does '
        'not hold the cancel back', () async {
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

      expect(presenter.dismissals, ['call2']);
    });

    test('with nothing remembered, a cancel naming a call still '
        'dismisses', () async {
      final presenter = _FakeRememberingPresenter();

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
        end: RingEnd.remoteEnded,
      );

      expect(presenter.dismissals, ['call1']);
    });

    test(
      'an unreadable remembered ring does not hold the cancel back',
      () async {
        final presenter = _FakeRememberingPresenter();
        SharedPreferences.setMockInitialValues({
          'calls.ringing_notification': '{not json',
        });

        await presenter.cancelIncoming(
          roomId: '!room:example.org',
          callId: 'call1',
          end: RingEnd.remoteEnded,
        );

        expect(presenter.dismissals, ['call1']);
      },
    );
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
        expect(await remembered(), isNull);
      },
    );
  });

  group('the CallKit presenter', () {
    const presenter = CallKitIncomingCallPresenter();
    const roomId = '!room:example.org';
    const ringing = (roomId: roomId, callId: 'call1');
    late RecordedMethodCalls native;
    late Future<Object?> Function() report;

    setUp(() {
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

        removeCallsChannel();
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
      removeCallsChannel();
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
      await presenter.cancelIncoming(roomId: roomId, callId: 'call1');

      expect(sent(), [
        for (final end in RingEnd.values)
          ['endIncomingCall', ended(reasons[end]!)],
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
      removeCallsChannel();

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
        'own, nothing remembered, no ring of its own reported', () async {
      await ringFor(isGroupCall: true);
      await pumpEventQueue();

      expect(callStyle.calls, isEmpty);
      expect(notifications.methods, isEmpty);
      expect(await remembered(), isNull);
      expect(await presenter.activeRing(), isNull);
    });
  });
}

class _FakeRememberingPresenter extends RememberingIncomingCallPresenter {
  _FakeRememberingPresenter({this.fails = false, this.presenting});

  final bool fails;
  final Future<void>? presenting;
  int presented = 0;
  final dismissals = <String?>[];

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
    await presenting;
    if (fails) throw StateError('no ring screen');
    presented++;
  }

  @override
  Future<void> forgetAndDismiss(String? callId) async {
    dismissals.add(callId);
    await clearRingingCall(await SharedPreferences.getInstance());
  }

  @override
  Future<RingingCallInfo?> activeRing() => rememberedRing();
}
