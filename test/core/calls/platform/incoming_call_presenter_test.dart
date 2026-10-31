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
import 'package:zuno/core/notifications/local_notifications.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  late RecordedNotifications notifications;
  late FakeNativeRing callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
  });

  tearDown(pumpEventQueue);

  Future<RingOutcome> ring(
    IncomingCallPresenter presenter, {
    String? caller,
    bool waiting = false,
  }) => presenter.showIncoming(
    name: 'Bob',
    caller: caller,
    callerId: '@bob:example.org',
    isVideo: true,
    roomId: '!room:example.org',
    callId: 'call1',
    isGroupCall: true,
    avatarBytes: Uint8List.fromList([1, 2, 3]),
    waiting: waiting,
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
        'sound need', () async {
      await ring(presenter);

      expect((callStyle.lastShow.arguments as Map).cast<String, Object?>(), {
        'channelId': 'calls_ringing_group',
        'text': 'Incoming video call',
        'name': 'Bob',
        'callerId': '@bob:example.org',
        'isVideo': true,
        'roomId': '!room:example.org',
        'callId': 'call1',
        'avatarBytes': Uint8List.fromList([1, 2, 3]),
        'ringtone': true,
        'vibrate': true,
      });
    });

    test('rings on the direct channel by default, the group channel for a '
        'group call', () async {
      Future<Object?> channelOf({
        required String callId,
        bool isGroupCall = false,
      }) async {
        await presenter.showIncoming(
          name: 'Bob',
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
        callStyle.ringing = null;

        await ring(presenter);

        final args = callStyle.lastShow.arguments as Map;
        expect(
          (ringtone: args['ringtone'], vibrate: args['vibrate']),
          asked,
          reason: '$settings',
        );
      }
    });

    test('a waiting ring leaves the ringtone setting for later, buzzes as '
        'set, and says answering ends the current call', () async {
      await ring(presenter, caller: 'Carol', waiting: true);

      final args = callStyle.lastShow.arguments as Map;
      expect(args['waitingText'], 'Answering ends your current call');
      expect(args['text'], 'Carol');
      expect(args['ringtone'], isTrue);
      expect(args['vibrate'], isTrue);
    });

    test('a normal ring says nothing about waiting', () async {
      await ring(presenter);

      final args = callStyle.lastShow.arguments as Map;
      expect(args.containsKey('waitingText'), isFalse);
    });

    test(
      'ringing aloud asks the native ring to ring the call it names',
      () async {
        await presenter.ringAloud('call1');

        expect(
          callStyle.named('ringIncomingCallStyleAloud').map((c) => c.arguments),
          [
            {'callId': 'call1'},
          ],
        );
      },
    );

    test('ringing aloud waits for a ring still being posted, so it is never '
        'lost before the ring exists', () async {
      final posting = ring(presenter, waiting: true);
      final aloud = presenter.ringAloud('call1');
      await Future.wait([posting, aloud]);

      expect(callStyle.methods.where((m) => m != 'cancelIncomingCallStyle'), [
        'showIncomingCallStyle',
        'ringIncomingCallStyleAloud',
      ]);
    });

    test('names the caller it is given on the second line', () async {
      await ring(presenter, caller: 'Carol');

      final args = callStyle.lastShow.arguments as Map;
      expect(args['name'], 'Bob');
      expect(args['text'], 'Carol');
    });

    test('at Nothing rings as a Zuno call, with no name or picture of the '
        'caller', () async {
      SharedPreferences.setMockInitialValues({
        notificationPreviewKey: NotificationPreview.nothing.name,
      });

      await ring(presenter, caller: 'Carol');

      final args = callStyle.lastShow.arguments as Map;
      expect(args['name'], 'Zuno call');
      expect(args['text'], 'Incoming video call');
      expect(args['avatarBytes'], isNull);
      expect(args['callerId'], '@bob:example.org');
    });

    test('at Name only names the caller and shows their picture', () async {
      SharedPreferences.setMockInitialValues({
        notificationPreviewKey: NotificationPreview.nameOnly.name,
      });

      await ring(presenter, caller: 'Carol');

      final args = callStyle.lastShow.arguments as Map;
      expect(args['name'], 'Bob');
      expect(args['text'], 'Carol');
      expect(args['avatarBytes'], Uint8List.fromList([1, 2, 3]));
    });

    test('asks for no buzz on a platform without vibration patterns', () async {
      ambientCapabilities = capabilitiesLike(
        androidCapabilities,
        vibrationPatterns: false,
      );

      await ring(presenter);

      expect((callStyle.lastShow.arguments as Map)['vibrate'], isFalse);
    });

    test('the ringtone native code plays ships with the app', () async {
      final tone = await rootBundle.load('assets/sounds/ringtone.ogg');

      expect(tone.lengthInBytes, greaterThan(0));
    });

    test('leaves the sound to the native side, so no engine going away can '
        'cut it short', () async {
      final dartSound = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in const [
        'zuno/vibration',
        'com.ryanheise.just_audio.methods',
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

    test('leaves the ring record to the native side, which forgets it in the '
        'same step that takes the ring down', () async {
      await callStyle.ringNatively(testRingingCall);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('zuno/call_style'),
            (call) async => null,
          );

      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );

      expect((await remembered())?.callId, 'call1');
    });

    test(
      'without the native side, rings nothing and reports no ring',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('zuno/call_style'),
              null,
            );

        expect(await ring(presenter), RingOutcome.unavailable);
        expect(await presenter.activeRing(), isNull);
      },
    );

    test('reports the ring native code says is ringing, and none once it '
        'stops', () async {
      await ring(presenter);
      expect(await presenter.activeRing(), testRingingCall);

      callStyle.ringing = null;
      expect(await presenter.activeRing(), isNull);
    });

    test('reports a ring native code started on its own', () async {
      await callStyle.ringNatively(testRingingCall);

      expect(await presenter.activeRing(), testRingingCall);
    });

    test('a ring native code could not show is no ring', () async {
      callStyle.showFails = true;

      expect(await ring(presenter), RingOutcome.unavailable);
      expect(await presenter.activeRing(), isNull);
    });

    test('a call native code says rang here already, declined or answered, '
        'does not ring again', () async {
      await callStyle.rememberRang(testRingingCall);

      expect(await ring(presenter), RingOutcome.filtered);
    });

    test('cancelling takes the ring down', () async {
      await ring(presenter);

      await presenter.cancelIncoming();

      expect(callStyle.calls.map((c) => c.method), [
        'showIncomingCallStyle',
        'cancelIncomingCallStyle',
      ]);
      expect(await presenter.activeRing(), isNull);
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

    test('rings a group call under the name it is given, and never asks '
        'CallKit', () async {
      final native = installFakeCallsChannel();

      final outcome = await presenter.showIncoming(
        name: 'Weekend hike',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: '!room:example.org',
        callId: 'call1',
        isGroupCall: true,
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
        'text': 'Incoming voice call',
        'name': 'Weekend hike',
        'callerId': '@bob:example.org',
        'isVideo': false,
        'roomId': '!room:example.org',
        'callId': 'call1',
        'avatarBytes': null,
        'ringtone': true,
        'vibrate': true,
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

    test('is adopted as shown and never taken down', () async {
      await ring(presenter);

      expect(await ring(presenter), RingOutcome.shown);
      await pumpEventQueue();

      expect(callStyle.methods, isNot(contains('cancelIncomingCallStyle')));
      expect(await presenter.activeRing(), testRingingCall);
    });

    test('rung by native code or another engine is adopted as shown, even '
        'before Android lists its notification', () async {
      await callStyle.ringNatively(testRingingCall);

      expect(await ring(presenter), RingOutcome.shown);
    });

    test('reads every answer native code gives, spelled as the shared '
        'fixture spells it', () async {
      final answers =
          pushFixture('call_style_answers_v1.json')['answers']
              as Map<String, dynamic>;
      const outcomes = {
        'shown': RingOutcome.shown,
        'alreadyRinging': RingOutcome.shown,
        'rangHere': RingOutcome.filtered,
        'busy': RingOutcome.filtered,
        'unavailable': RingOutcome.unavailable,
      };
      expect(answers.keys.toSet(), outcomes.keys.toSet());

      for (final MapEntry(:key, :value) in answers.entries) {
        recordMethodChannel(
          'zuno/call_style',
          reply: (call) async =>
              call.method == 'showIncomingCallStyle' ? value : null,
        );
        expect(await ring(presenter), outcomes[key], reason: key);
      }
    });

    test('never rings over another call that still rings', () async {
      await callStyle.ringNatively((
        roomId: '!other:example.org',
        callId: 'call0',
        callerId: '@ann:example.org',
        isVideo: false,
      ));

      expect(await ring(presenter), RingOutcome.filtered);
      expect(callStyle.ringing?.callId, 'call0');
    });

    test('rings again once its ring was cancelled', () async {
      await ring(presenter);
      await presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );

      expect(await ring(presenter), RingOutcome.shown);
      expect(posts(), hasLength(2));
    });

    test('does not stop a different call from ringing as before', () async {
      await ring(presenter);

      await presenter.showIncoming(
        name: 'Carol',
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

    test('a cancel that lands while the call is still being presented reaches '
        'native code only once it is up', () async {
      final presenting = Completer<void>();
      final native = recordMethodChannel(
        'zuno/call_style',
        reply: (call) async {
          if (call.method != 'showIncomingCallStyle') return null;
          await presenting.future;
          return 'shown';
        },
      );

      final shown = ring(presenter);
      await pumpEventQueue();
      final cancelled = presenter.cancelIncoming(
        roomId: '!room:example.org',
        callId: 'call1',
      );
      await pumpEventQueue();
      expect(native.methods, ['showIncomingCallStyle']);

      presenting.complete();
      await Future.wait([shown, cancelled]);

      expect(native.methods, [
        'showIncomingCallStyle',
        'cancelIncomingCallStyle',
      ]);
    });
  });

  test('presenting a ring takes the app\'s decline route back', () async {
    await CallNotificationService.instance.initialize();
    final stranger = ReceivePort();
    addTearDown(stranger.close);
    IsolateNameServer.removePortNameMapping(declinePortName);
    IsolateNameServer.registerPortWithName(stranger.sendPort, declinePortName);

    await ring(const AndroidIncomingCallPresenter());

    expect(LocalNotifications.instance.stillHoldsDeclinePort(), isTrue);
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
      String? caller,
    }) => presenter.showIncoming(
      name: 'Bob',
      caller: caller,
      callerId: '@bob:example.org',
      isVideo: isVideo,
      roomId: roomId,
      callId: callId,
      isGroupCall: isGroupCall,
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

    test('reports the ring to CallKit under the name it is given alone, for '
        'a group call too', () async {
      expect(await ringFor(), RingOutcome.shown);
      await ringFor(isGroupCall: true, isVideo: true, caller: 'Carol');

      expect(sent(), [
        ['reportIncomingCall', reported(name: 'Bob')],
        ['reportIncomingCall', reported(name: 'Bob', isVideo: true)],
      ]);
    });

    test('reports a waiting ring as any other, and leaves ringing aloud to '
        'CallKit', () async {
      await presenter.showIncoming(
        name: 'Bob',
        callerId: '@bob:example.org',
        isVideo: false,
        roomId: roomId,
        callId: 'call1',
        waiting: true,
      );
      await presenter.ringAloud('call1');

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
