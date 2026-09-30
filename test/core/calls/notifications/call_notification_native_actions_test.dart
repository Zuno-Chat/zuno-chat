import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CallNotificationService service;
  late RecordedNotifications notifications;

  Future<List<T>> collect<T>(
    Stream<T> stream,
    Future<void> Function() act,
  ) async {
    final seen = <T>[];
    final sub = stream.listen(seen.add);
    await act();
    await pumpEventQueue();
    await sub.cancel();
    return seen;
  }

  const bobsCall = {
    'roomId': '!room:example.org',
    'callId': 'call1',
    'callerId': '@bob:example.org',
    'isVideo': true,
  };

  const bobsRing = (
    roomId: '!room:example.org',
    callId: 'call1',
    callerId: '@bob:example.org',
    isVideo: true,
  );

  const callOne = {'roomId': '!room:example.org', 'callId': 'call1'};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    service = CallNotificationService(capabilities: iosCapabilities);
    await service.initialize(claimDeclinePort: false);
  });

  test('an answer from the system call screen reaches whoever handles call '
      'actions', () async {
    final action = service.onAction.first;

    await sendFromNative('answerCall', bobsCall);

    final response = await action.timeout(const Duration(seconds: 2));
    expect(response.action, CallNotificationAction.accept);
    expect(response.call, (
      roomId: '!room:example.org',
      callId: 'call1',
      callerId: '@bob:example.org',
      isVideo: true,
    ));
  });

  test('a decline from the system call screen does too', () async {
    final action = service.onAction.first;

    await sendFromNative('declineCall', bobsCall);

    expect(
      (await action.timeout(const Duration(seconds: 2))).action,
      CallNotificationAction.decline,
    );
  });

  test('an action that arrives before anything listens, as on a cold start '
      'from the lock screen, is kept for the launch check, once', () async {
    await sendFromNative('answerCall', bobsCall);

    final launch = await service.takeLaunchCallActionFromNotification();
    expect(launch?.action, CallNotificationAction.accept);
    expect(launch?.call.callId, 'call1');
    expect(await service.takeLaunchCallActionFromNotification(), isNull);
  });

  test('an action with no call to name is dropped', () async {
    final seen = <CallNotificationResponse>[];
    final sub = service.onAction.listen(seen.add);
    addTearDown(sub.cancel);

    await sendFromNative('answerCall', {'roomId': '!room:example.org'});
    await sendFromNative('answerCall', null);

    expect(seen, isEmpty);
    expect(await service.takeLaunchCallActionFromNotification(), isNull);
  });

  group('what the system call reports reaches its listeners', () {
    test('a hang up names the call CallKit ended', () async {
      final hangUps = await collect(
        service.onHangUp,
        () => sendFromNative('hangUpCall', callOne),
      );

      expect(hangUps, ['call1']);
    });

    test('a hang up with no arguments, as the Android ongoing-call '
        'notification sends it, names no call', () async {
      final hangUps = await collect(
        service.onHangUp,
        () => sendFromNative('hangUpCall', null),
      );

      expect(hangUps, [null]);
    });

    test('a mute and an unmute from the system call screen carry their call '
        'and state, in order', () async {
      final mutes = await collect(service.onSystemMute, () async {
        await sendFromNative('setMuted', {...callOne, 'muted': true});
        await sendFromNative('setMuted', {...callOne, 'muted': false});
      });

      expect(mutes, [
        (callId: 'call1', muted: true),
        (callId: 'call1', muted: false),
      ]);
    });

    test('a ring the system ended unanswered carries the whole call', () async {
      final ended = await collect(
        service.onRingEnded,
        () => sendFromNative('ringEnded', bobsCall),
      );

      expect(ended, [bobsRing]);
    });

    test('a ring the system still shows carries the whole call', () async {
      final ringing = await collect(
        service.onSystemRinging,
        () => sendFromNative('ringing', bobsCall),
      );

      expect(ringing, [bobsRing]);
    });

    test('a system call that failed to start names its call', () async {
      final failed = await collect(
        service.onSystemCallFailed,
        () => sendFromNative('callFailed', callOne),
      );

      expect(failed, ['call1']);
    });

    test(
      'an audio route change is passed on as the platform sent it',
      () async {
        final routes = await collect(
          service.onAudioRouteChanged,
          () => sendFromNative('audioRouteChanged', {
            'route': 'bluetooth',
            'headsets': ['wiredHeadset', 'bluetooth'],
          }),
        );

        expect(routes, [
          {
            'route': 'bluetooth',
            'headsets': ['wiredHeadset', 'bluetooth'],
          },
        ]);
      },
    );
  });

  group('a report missing what it needs is dropped', () {
    test('a mute without its call, or without a true or false state', () async {
      final mutes = await collect(service.onSystemMute, () async {
        await sendFromNative('setMuted', callOne);
        await sendFromNative('setMuted', {'muted': true});
        await sendFromNative('setMuted', {...callOne, 'muted': 'yes'});
        await sendFromNative('setMuted', {'callId': 7, 'muted': true});
        await sendFromNative('setMuted', null);
      });

      expect(mutes, isEmpty);
    });

    test('a ring end or a ringing report without both its room and '
        'call', () async {
      Future<void> reportBroken(String method) async {
        await sendFromNative(method, {'callId': 'call1'});
        await sendFromNative(method, {'roomId': '!room:example.org'});
        await sendFromNative(method, {'roomId': 7, 'callId': 'call1'});
        await sendFromNative(method, null);
      }

      final ended = await collect(
        service.onRingEnded,
        () => reportBroken('ringEnded'),
      );
      final ringing = await collect(
        service.onSystemRinging,
        () => reportBroken('ringing'),
      );

      expect(ended, isEmpty);
      expect(ringing, isEmpty);
    });

    test('a failure without a call id', () async {
      final failed = await collect(service.onSystemCallFailed, () async {
        await sendFromNative('callFailed', {'roomId': '!room:example.org'});
        await sendFromNative('callFailed', {'callId': 7});
        await sendFromNative('callFailed', null);
      });

      expect(failed, isEmpty);
    });

    test('an audio route change that is not a map', () async {
      final routes = await collect(service.onAudioRouteChanged, () async {
        await sendFromNative('audioRouteChanged', 'speaker');
        await sendFromNative('audioRouteChanged', ['speaker']);
        await sendFromNative('audioRouteChanged', null);
      });

      expect(routes, isEmpty);
    });
  });

  group('starting the service', () {
    test('on iOS tells CallKit a new Dart is up, once however often it '
        'starts', () async {
      final toNative = installFakeCallsChannel();
      final fresh = CallNotificationService(capabilities: iosCapabilities);

      await fresh.initialize(claimDeclinePort: false);
      await fresh.initialize(claimDeclinePort: false);

      expect(toNative.calls.map((c) => [c.method, c.arguments]), [
        ['resetSystemCalls', null],
      ]);
    });

    test('on Android sends nothing on the calls channel', () async {
      final toNative = installFakeCallsChannel();
      final fresh = CallNotificationService(capabilities: androidCapabilities);

      await fresh.initialize(claimDeclinePort: false);

      expect(toNative.calls, isEmpty);
    });

    test('on iOS without the calls plugin still finishes starting and hears '
        'the system call', () async {
      notifications.methods.clear();
      final fresh = CallNotificationService(capabilities: iosCapabilities);

      await fresh.initialize(claimDeclinePort: false);
      final hangUps = await collect(
        fresh.onHangUp,
        () => sendFromNative('hangUpCall', callOne),
      );

      expect(notifications.methods, contains('initialize'));
      expect(hangUps, ['call1']);
    });
  });

  group('picture-in-picture', () {
    Future<void> offerPictureInPicture(CallNotificationService service) =>
        service.setPictureInPicture(
          eligible: true,
          aspectWidth: 640,
          aspectHeight: 480,
        );

    test('on Android the call screen\'s eligibility and shape reach the '
        'platform', () async {
      final toNative = installFakeCallsChannel();

      await offerPictureInPicture(
        CallNotificationService(capabilities: androidCapabilities),
      );

      expect(toNative.calls.map((c) => [c.method, c.arguments]), [
        [
          'setPictureInPicture',
          {'eligible': true, 'aspectWidth': 640, 'aspectHeight': 480},
        ],
      ]);
    });

    test('on iOS nothing is sent', () async {
      final toNative = installFakeCallsChannel();

      await offerPictureInPicture(
        CallNotificationService(capabilities: iosCapabilities),
      );

      expect(toNative.calls, isEmpty);
    });
  });

  group('events CallKit queued before Dart listened', () {
    test('are taken once and replayed in the order they were queued', () async {
      final toNative = installFakeCallsChannel(
        reply: (call) => call.method == 'takeCallEvents'
            ? [
                {'method': 'ringing', 'arguments': bobsCall},
                {
                  'method': 'setMuted',
                  'arguments': {...callOne, 'muted': true},
                },
                {'method': 'answerCall', 'arguments': bobsCall},
                {'method': 'hangUpCall', 'arguments': callOne},
                {
                  'method': 'ringEnded',
                  'arguments': {...bobsCall, 'callId': 'call2'},
                },
                {
                  'method': 'callFailed',
                  'arguments': {...callOne, 'callId': 'call3'},
                },
              ]
            : null,
      );
      final replayed = <String>[];
      final subs = [
        service.onSystemRinging.listen(
          (call) => replayed.add('ringing ${call.callId}'),
        ),
        service.onSystemMute.listen(
          (mute) => replayed.add('muted ${mute.callId} ${mute.muted}'),
        ),
        service.onAction.listen(
          (response) =>
              replayed.add('${response.action.name} ${response.call.callId}'),
        ),
        service.onHangUp.listen((callId) => replayed.add('hang up $callId')),
        service.onRingEnded.listen(
          (call) => replayed.add('ring ended ${call.callId}'),
        ),
        service.onSystemCallFailed.listen(
          (callId) => replayed.add('failed $callId'),
        ),
      ];
      for (final sub in subs) {
        addTearDown(sub.cancel);
      }

      await service.takeQueuedNativeCalls();
      await pumpEventQueue();

      expect(toNative.calls.map((c) => [c.method, c.arguments]), [
        ['takeCallEvents', null],
      ]);
      expect(replayed, [
        'ringing call1',
        'muted call1 true',
        'accept call1',
        'hang up call1',
        'ring ended call2',
        'failed call3',
      ]);
    });

    test('a queued answer that nothing listens for yet is kept for the '
        'launch check', () async {
      installFakeCallsChannel(
        reply: (call) => call.method == 'takeCallEvents'
            ? [
                {'method': 'answerCall', 'arguments': bobsCall},
              ]
            : null,
      );

      await service.takeQueuedNativeCalls();

      final launch = await service.takeLaunchCallActionFromNotification();
      expect(launch?.action, CallNotificationAction.accept);
      expect(launch?.call, bobsRing);
    });

    test('entries that are not events are skipped and the rest still '
        'replayed', () async {
      installFakeCallsChannel(
        reply: (call) => call.method == 'takeCallEvents'
            ? [
                null,
                'ringing',
                {'method': 7, 'arguments': bobsCall},
                {'arguments': bobsCall},
                {'method': 'ringing', 'arguments': bobsCall},
              ]
            : null,
      );

      final ringing = await collect(
        service.onSystemRinging,
        service.takeQueuedNativeCalls,
      );

      expect(ringing, [bobsRing]);
    });

    test('an empty or missing queue replays nothing', () async {
      Object? queue;
      installFakeCallsChannel(
        reply: (call) => call.method == 'takeCallEvents' ? queue : null,
      );

      final hangUps = await collect(service.onHangUp, () async {
        queue = const <Object?>[];
        await service.takeQueuedNativeCalls();
        queue = null;
        await service.takeQueuedNativeCalls();
      });

      expect(hangUps, isEmpty);
    });

    test('without the calls plugin there is nothing to replay and no '
        'error', () async {
      final hangUps = await collect(
        service.onHangUp,
        service.takeQueuedNativeCalls,
      );

      expect(hangUps, isEmpty);
    });
  });
}
