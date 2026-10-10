import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_controller.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/cloudflare/webrtc_backend.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_controls.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';
import 'package:zuno/features/calls/presentation/call_status_widgets.dart';
import 'package:zuno/features/calls/presentation/call_view.dart';
import 'package:zuno/features/calls/presentation/participant_tile.dart';
import 'package:zuno/features/verification/presentation/why_confirm_sheet.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import 'call_page_harness.dart';

void main() {
  group('with a real session', () {
    late Room room;

    setUp(() {
      installFakeLocalNotifications();
      silenceMethodChannels(const [
        'zuno/calls',
        'zuno/vibration',
        'flutter.baseflow.com/permissions/methods',
        'wakelock_plus',
      ]);
      room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
    });

    for (final kind in CallKind.values) {
      testWidgets('a $kind call builds before it connects, dark, with '
          'End call and Minimize ready', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 640);
        addTearDown(tester.view.reset);
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-${kind.name}',
          kind: kind,
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(activeCallProvider.notifier).set(session);
        final call = container.read(activeCallControllerProvider)!;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: zunoLightTheme,
              home: CallPage(call: call),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(find.text('Connecting…'), findsOneWidget);
        expect(find.byTooltip('End call'), findsOneWidget);
        expect(find.byTooltip('Minimize call'), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byType(CallControls))).brightness,
          Brightness.dark,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      });
    }
  });

  FakeCallSession sessionFor(
    CallKind kind, {
    CallSessionRole role = CallSessionRole.callee,
    CallSessionPhase phase = CallSessionPhase.connecting,
  }) => FakeCallSession(
    room: CallPageHarness.buildRoom(),
    kind: kind,
    role: role,
    phase: phase,
  );

  Future<FakeCallSession> talking(
    CallPageHarness harness,
    CallKind kind,
  ) async {
    final session = sessionFor(kind);
    await harness.open(session);
    session.engine.participants = [localParticipant(), remoteParticipant()];
    session.moveTo(CallSessionPhase.active);
    await harness.settle();
    return session;
  }

  group('starting a call', () {
    testWidgets('a voice call stays at the ear: earpiece, screen off near the '
        'face, no wakelock, and the ongoing-call notice shown', (tester) async {
      final harness = CallPageHarness(tester);
      await harness.open(sessionFor(CallKind.voice));

      expect(harness.argsOf('startCallAudio'), [
        {'route': 'earpiece'},
      ]);
      expect(harness.speakerIcon, Icons.hearing_outlined);
      expect(harness.proximityScreenOff, isTrue);
      expect(harness.wakelockToggles, isEmpty);
      expect(harness.argsOf('startCallForegroundService'), [
        {
          'title': 'Weekend hike',
          'text': 'Tap to return to the call',
          'withCamera': false,
        },
      ]);
      expect(harness.showOverLockscreen, isTrue);
      await harness.close();
    });

    testWidgets('a video call starts on the speaker with the screen kept on', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      await harness.open(sessionFor(CallKind.video));

      expect(harness.argsOf('startCallAudio'), [
        {'route': 'speaker'},
      ]);
      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(harness.proximityScreenOff, isFalse);
      expect(harness.wakelockToggles, [true]);
      expect(
        (harness.argsOf('startCallForegroundService').single
            as Map)['withCamera'],
        isTrue,
      );
      await harness.close();
    });

    testWidgets('a headset already connected takes the sound, even on a video '
        'call', (tester) async {
      final harness = CallPageHarness(tester)..headsets = ['bluetooth'];
      await harness.open(sessionFor(CallKind.video));

      expect(harness.argsOf('startCallAudio'), [
        {'route': 'bluetooth'},
      ]);
      expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);
      expect(harness.proximityScreenOff, isFalse);
      await harness.close();
    });

    testWidgets('without the microphone nothing starts: no notice, no route, '
        'no screen handling', (tester) async {
      final harness = CallPageHarness(tester);
      final session = sessionFor(CallKind.voice)..microphoneGranted = false;
      await harness.open(session);

      expect(harness.count('startCallForegroundService'), 0);
      expect(harness.audioRoute, isNull);
      expect(harness.proximityScreenOff, isNull);
      expect(harness.showOverLockscreen, isNull);
      await harness.close();
    });

    testWidgets('a call already over when the screen opens closes it again', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      await harness.open(
        sessionFor(CallKind.voice, phase: CallSessionPhase.ended),
      );

      expect(find.byType(CallPage), findsNothing);
      expect(find.text('Chat'), findsOneWidget);
      expect(harness.count('startCallForegroundService'), 0);
    });
  });

  group('headsets mid-call', () {
    testWidgets('connecting a headset moves the sound to it and shows it', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      await talking(harness, CallKind.voice);

      await harness.changeHeadsets(['bluetooth']);

      expect(harness.audioRoute, 'bluetooth');
      expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);
      expect(harness.proximityScreenOff, isFalse);
      await harness.close();
    });

    for (final (kind, fallback) in [
      (CallKind.voice, 'earpiece'),
      (CallKind.video, 'speaker'),
    ]) {
      testWidgets('unplugging the headset on a $kind call goes back to the '
          '$fallback', (tester) async {
        final harness = CallPageHarness(tester)..headsets = ['wiredHeadset'];
        await talking(harness, kind);
        expect(harness.audioRoute, 'wiredHeadset');

        await harness.changeHeadsets([]);

        expect(harness.audioRoute, fallback);
        expect(harness.proximityScreenOff, kind == CallKind.voice);
        await harness.close();
      });
    }

    testWidgets('a device change that connects nothing new leaves the sound '
        'where it is', (tester) async {
      final harness = CallPageHarness(tester)..headsets = ['bluetooth'];
      await talking(harness, CallKind.voice);
      final before = harness.audioRouteChanges;

      await harness.changeHeadsets(['bluetooth']);

      expect(harness.audioRouteChanges, before);
      expect(harness.audioRoute, 'bluetooth');
      await harness.close();
    });

    testWidgets('the speaker button leaves the headset for the speaker and '
        'comes back to it', (tester) async {
      final harness = CallPageHarness(tester)..headsets = ['bluetooth'];
      await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('Turn speaker on'));
      await harness.settle();
      expect(harness.audioRoute, 'speaker');
      expect(harness.speakerIcon, Icons.volume_up_outlined);

      await tester.tap(find.byTooltip('Turn speaker off'));
      await harness.settle();
      expect(harness.audioRoute, 'bluetooth');
      expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);
      await harness.close();
    });
  });

  group('during a call', () {
    testWidgets('the speaker button switches ear and speaker, and the screen '
        'handling with it', (tester) async {
      final harness = CallPageHarness(tester);
      await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('Turn speaker on'));
      await harness.settle();
      expect(harness.audioRoute, 'speaker');
      expect(harness.proximityScreenOff, isFalse);

      await tester.tap(find.byTooltip('Turn speaker off'));
      await harness.settle();
      expect(harness.audioRoute, 'earpiece');
      expect(harness.proximityScreenOff, isTrue);
      await harness.close();
    });

    testWidgets('mute asks the engine and republishes membership', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('Mute'));
      await harness.settle();

      expect(session.engine.microphoneMutedRequests, [true]);
      expect(session.membershipRefreshes, 1);
      await harness.close();
    });

    testWidgets('a camera that will not turn on says so, and is reported', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);
      session.engine.cameraError = StateError('camera in use');

      final reports = await reportsDuring(() async {
        await tester.tap(find.byTooltip('Turn camera on'));
        await harness.settle();
      });

      expect(session.engine.cameraEnabledRequests, [true]);
      expect(find.text(cameraDidNotTurnOnMessage), findsOneWidget);
      expect(reports, contains('toggle camera'));
      expect(tester.takeException(), isNull);
      await harness.close();
    });

    testWidgets('a camera refused at the prompt says so, and is not '
        'reported', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);
      session.engine.cameraError = const CameraRefused();

      final reports = await reportsDuring(() async {
        await tester.tap(find.byTooltip('Turn camera on'));
        await harness.settle();
      });

      expect(find.text(cameraDidNotTurnOnMessage), findsOneWidget);
      expect(reports, isEmpty);
      expect(tester.takeException(), isNull);
      await harness.close();
    });

    testWidgets('a camera that fails to turn off does not claim it failed to '
        'turn on', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);
      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(),
      ]);
      await harness.settle();
      session.engine.cameraError = StateError('camera stuck');

      await tester.tap(find.byTooltip('Turn camera off'));
      await harness.settle();

      expect(session.engine.cameraEnabledRequests, [false]);
      expect(find.text(cameraDidNotTurnOnMessage), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.close();
    });

    testWidgets('a voice call whose camera will not turn on stays a voice '
        'call and says so', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);
      session.engine.cameraError = StateError('camera refused');

      await tester.tap(find.byTooltip('Switch to video call'));
      await harness.settle();

      expect(find.text(cameraDidNotTurnOnMessage), findsOneWidget);
      expect(session.kind, CallKind.voice);
      expect(harness.wakelockToggles, isEmpty);
      expect(tester.takeException(), isNull);
      await harness.close();
    });

    testWidgets('the other side\'s camera makes the call eligible for '
        'picture-in-picture, and turning it off ends that', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);
      expect(harness.pictureInPictureEligible, isFalse);

      session.engine.setParticipants([
        localParticipant(),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();
      expect(harness.pictureInPictureEligible, isTrue);
      expect(
        harness.webrtc.where(
          (c) =>
              c.method == 'videoRendererSetSrcObject' &&
              (c.arguments as Map)['streamId'] == '@ann:example.org-video',
        ),
        isNotEmpty,
      );

      session.engine.setParticipants([localParticipant(), remoteParticipant()]);
      await harness.settle();
      expect(harness.pictureInPictureEligible, isFalse);
      await harness.close();
    });

    testWidgets('picture-in-picture names the video of the person it shows, '
        'never your own', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);

      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(),
        remoteParticipant(userId: '@bob:example.org', camera: true),
      ]);
      await harness.settle();
      expect(harness.pictureInPictureVideo, (
        streamId: '@bob:example.org-video',
        ownerTag: 'local',
      ));

      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(),
      ]);
      await harness.settle();
      expect(harness.pictureInPictureEligible, isFalse);
      expect(harness.pictureInPictureVideo, (streamId: null, ownerTag: null));
      await harness.close();
    });

    testWidgets('an ended call takes back the video it offered', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);
      session.engine.setParticipants([
        localParticipant(),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();
      expect(harness.pictureInPictureVideo?.streamId, '@ann:example.org-video');

      session.end();
      await harness.settle();

      expect(harness.pictureInPictureEligible, isFalse);
      expect(harness.pictureInPictureVideo, (streamId: null, ownerTag: null));
    });

    testWidgets('you appear as yourself, so your own picture shows', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      await talking(harness, CallKind.video);

      final view = tester.widget<CallView>(find.byType(CallView));
      expect(view.local?.user?.id, '@me:example.org');
      expect(view.local?.user?.calcDisplayname(), 'Me');
      expect(view.remote.single.user?.id, '@ann:example.org');
      await harness.close();
    });

    testWidgets('a burst of roster changes gives each person one renderer', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = sessionFor(CallKind.video);
      await harness.open(session);
      session.moveTo(CallSessionPhase.active);
      await harness.settle();

      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(),
      ]);
      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();

      expect(
        harness.webrtc.where((c) => c.method == 'createVideoRenderer'),
        hasLength(2),
      );
      await harness.close();
    });

    testWidgets('someone leaving releases their video renderer', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.video);
      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();
      final created = harness.webrtc
          .where((c) => c.method == 'createVideoRenderer')
          .length;
      expect(created, 2);

      session.engine.setParticipants([localParticipant(camera: true)]);
      await harness.settle();

      expect(
        harness.webrtc.where((c) => c.method == 'videoRendererDispose'),
        hasLength(1),
      );
      await harness.close();
    });

    testWidgets('a reconnecting engine shows on screen', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);

      session.engine.setStatus(CallEngineStatus.reconnecting);
      await harness.settle();

      expect(find.byType(ReconnectingNotice), findsOneWidget);
      await harness.close();
    });
  });

  group('before the call connects', () {
    testWidgets('every button acts the moment the call starts', (tester) async {
      final harness = CallPageHarness(tester);
      final session = sessionFor(CallKind.video);
      session.engine.participants = [localParticipant(camera: true)];
      await harness.open(session);

      for (final tooltip in [
        'Mute',
        'Turn camera off',
        'Switch camera',
        'Turn speaker off',
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await harness.settle();
      }

      expect(session.phase, CallSessionPhase.connecting);
      expect(session.engine.microphoneMutedRequests, [true]);
      expect(session.engine.cameraEnabledRequests, [false]);
      expect(session.engine.switchCameraCalls, 1);
      expect(harness.audioRoute, 'earpiece');
      expect(find.byType(ParticipantTile), findsNothing);
      await harness.close();
    });
  });

  group('ringback', () {
    testWidgets('a caller hears ringback until the other side joins', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = sessionFor(CallKind.voice, role: CallSessionRole.caller);
      await harness.open(session);
      expect(harness.ringbackPlaying, isTrue);

      session.remoteJoins();
      await harness.settle();

      expect(harness.ringbackPlaying, isFalse);
      await harness.close();
    });

    testWidgets('the one being called hears no ringback', (tester) async {
      final harness = CallPageHarness(tester);
      await harness.open(sessionFor(CallKind.voice));

      expect(harness.count('startRingbackTone'), 0);
      await harness.close();
    });
  });

  group('ending a call', () {
    testWidgets('End call asks the session to hang up', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('End call'));
      await harness.settle();

      expect(session.hangUps, 1);
      await harness.close();
    });

    testWidgets('an ended call closes the screen and releases the notice, '
        'the lock screen, the ear sensor, the wakelock and the active call', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);

      session.end();
      await harness.settle();

      expect(find.byType(CallPage), findsNothing);
      expect(find.text('Chat'), findsOneWidget);
      expect(harness.count('stopCallForegroundService'), 1);
      expect(harness.showOverLockscreen, isFalse);
      expect(harness.proximityScreenOff, isFalse);
      expect(harness.pictureInPictureEligible, isFalse);
      expect(harness.wakelockToggles, [false]);
      expect(harness.container.read(activeCallProvider), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed call says why once the screen closes', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);

      session.end(reason: CallEndReason.failed, message: 'Connection lost');
      await harness.settle();

      expect(find.byType(CallPage), findsNothing);
      expect(find.text('Connection lost'), findsOneWidget);
    });

    testWidgets('a wakelock that will not switch never stops a call from '
        'starting or winding down', (tester) async {
      final harness = CallPageHarness(tester)..wakelockFails = true;
      final session = await talking(harness, CallKind.video);
      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();
      expect(harness.audioRoute, 'speaker');

      session.end(reason: CallEndReason.failed, message: 'Connection lost');
      await harness.settle();

      expect(find.text('Connection lost'), findsOneWidget);
      expect(
        harness.webrtc.where((c) => c.method == 'videoRendererDispose'),
        hasLength(2),
      );
    });

    testWidgets('a headset connected after the call ended changes nothing', (
      tester,
    ) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness, CallKind.voice);
      session.end();
      await harness.settle();
      final before = harness.audioRouteChanges;

      await harness.changeHeadsets(['bluetooth']);

      expect(harness.audioRouteChanges, before);
    });
  });

  group('confirming the person on the call', () {
    const confirmAnn = 'Confirm it is really @ann';
    const ready = AccountSecurityFacts(
      recoveryExists: true,
      thisDeviceHasIdentityKeys: true,
      keyBackupExists: true,
      keyBackupUsableHere: true,
      unapprovedOtherDevices: 0,
    );

    Future<({CallPageHarness harness, SharedPreferences prefs})> talkingTo(
      WidgetTester tester, {
      UserTrustState trust = UserTrustState.unconfirmed,
      AccountSecurityFacts facts = ready,
      bool theirDeviceApproved = true,
      bool directChat = true,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final harness = CallPageHarness(
        tester,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          userTrustProvider.overrideWith((ref, _) => trust),
          deviceApprovedByOwnerProvider.overrideWith(
            (ref, device) =>
                device == (userId: '@ann:example.org', deviceId: 'ANN') &&
                theirDeviceApproved,
          ),
          accountSecurityFactsProvider.overrideWith(
            (ref) => Stream.value(facts),
          ),
        ],
      );
      final session = sessionFor(CallKind.voice);
      if (directChat) {
        session.room.client.accountData['m.direct'] = BasicEvent(
          type: 'm.direct',
          content: {
            '@ann:example.org': [session.room.id],
          },
        );
      }
      await harness.open(session);
      session.engine.participants = [localParticipant(), remoteParticipant()];
      session.moveTo(CallSessionPhase.active);
      await harness.settle();
      return (harness: harness, prefs: prefs);
    }

    Future<void> halfAMinute(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
    }

    testWidgets('after half a minute with someone not yet confirmed, it '
        'offers to confirm them', (tester) async {
      final call = await talkingTo(tester);

      expect(find.text(confirmAnn), findsNothing);
      await halfAMinute(tester);

      expect(find.text(confirmAnn), findsOneWidget);
      await call.harness.close();
    });

    testWidgets('an offer earned while the call was minimized shows as soon '
        'as the call is reopened', (tester) async {
      final call = await talkingTo(tester);
      await call.harness.minimize();

      await halfAMinute(tester);
      showCallScreen(
        call.harness.navigatorKey.currentState!,
        call.harness.call,
      );
      await call.harness.settle();

      expect(find.text(confirmAnn), findsOneWidget);
      await call.harness.close();
    });

    testWidgets('someone already confirmed is never offered', (tester) async {
      final call = await talkingTo(tester, trust: UserTrustState.confirmed);
      await halfAMinute(tester);

      expect(find.text(confirmAnn), findsNothing);
      await call.harness.close();
    });

    testWidgets('a device that cannot confirm anyone yet is not offered', (
      tester,
    ) async {
      final call = await talkingTo(
        tester,
        facts: const AccountSecurityFacts(
          recoveryExists: false,
          thisDeviceHasIdentityKeys: false,
          keyBackupExists: false,
          keyBackupUsableHere: false,
          unapprovedOtherDevices: 0,
        ),
      );
      await halfAMinute(tester);

      expect(find.text(confirmAnn), findsNothing);
      await call.harness.close();
    });

    testWidgets('someone calling from a device they have not approved is not '
        'offered', (tester) async {
      final call = await talkingTo(tester, theirDeviceApproved: false);
      await halfAMinute(tester);

      expect(find.text(confirmAnn), findsNothing);
      await call.harness.close();
    });

    testWidgets('a room call is never offered', (tester) async {
      final call = await talkingTo(tester, directChat: false);
      await halfAMinute(tester);

      expect(find.text(confirmAnn), findsNothing);
      await call.harness.close();
    });

    testWidgets('it opens the explanation, and Not now stops offering it for '
        'that person', (tester) async {
      final call = await talkingTo(tester);
      await halfAMinute(tester);

      await tester.tap(find.text(confirmAnn));
      await call.harness.settle();
      expect(find.byType(WhyConfirmSheet), findsOneWidget);

      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await call.harness.settle();

      expect(find.byType(WhyConfirmSheet), findsNothing);
      expect(find.text(confirmAnn), findsNothing);
      expect(
        call.prefs.getBool('security.call_confirm_declined.@ann:example.org'),
        isTrue,
      );
      await call.harness.close();
    });

    testWidgets('closing the explanation without answering keeps the offer', (
      tester,
    ) async {
      final call = await talkingTo(tester);
      await halfAMinute(tester);

      await tester.tap(find.text(confirmAnn));
      await call.harness.settle();
      await tester.binding.handlePopRoute();
      await call.harness.settle();

      expect(find.byType(WhyConfirmSheet), findsNothing);
      expect(find.byType(CallPage), findsOneWidget);
      expect(find.text(confirmAnn), findsOneWidget);
      await call.harness.close();
    });
  });

  testWidgets('a call that ends under an open sheet closes both', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    final session = await talking(harness, CallKind.voice);
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.byType(CallView)),
        builder: (_) => const Text('Over the call'),
      ),
    );
    await harness.settle();
    expect(find.text('Over the call'), findsOneWidget);

    session.end();
    await harness.settle();

    expect(find.text('Over the call'), findsNothing);
    expect(find.byType(CallPage), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
  });
}
