import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_router.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/platform_capabilities.dart';
import 'call_page_harness.dart';

void main() {
  Future<FakeCallSession> talking(
    CallPageHarness harness, {
    CallKind kind = CallKind.voice,
    bool remoteCamera = false,
  }) async {
    final session = FakeCallSession(
      room: CallPageHarness.buildRoom(),
      kind: kind,
    );
    await harness.open(session);
    session.engine.participants = [
      localParticipant(),
      remoteParticipant(camera: remoteCamera),
    ];
    session.moveTo(CallSessionPhase.active);
    await harness.settle();
    return session;
  }

  testWidgets('Back closes the call screen and the call keeps running', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    final session = await talking(harness);

    await tester.binding.handlePopRoute();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
    expect(session.hangUps, 0);
    expect(harness.count('stopCallForegroundService'), 0);
    expect(harness.container.read(activeCallProvider), same(session));
    await harness.close();
  });

  testWidgets('the minimize button closes the call screen too', (tester) async {
    final harness = CallPageHarness(tester);
    final session = await talking(harness);

    await harness.minimize();

    expect(find.byType(CallPage), findsNothing);
    expect(session.hangUps, 0);
    await harness.close();
  });

  testWidgets('minimized, the ear sensor and the lock-screen display are '
      'off; reopened, both come back', (tester) async {
    final harness = CallPageHarness(tester);
    await talking(harness);
    expect(harness.proximityScreenOff, isTrue);
    expect(harness.showOverLockscreen, isTrue);

    await harness.minimize();

    expect(harness.proximityScreenOff, isFalse);
    expect(harness.showOverLockscreen, isFalse);

    showCallScreen(harness.navigatorKey.currentState!, harness.call);
    await harness.settle();

    expect(find.byType(CallPage), findsOneWidget);
    expect(harness.proximityScreenOff, isTrue);
    expect(harness.showOverLockscreen, isTrue);
    await harness.close();
  });

  testWidgets('opening the call screen twice shows it once', (tester) async {
    final harness = CallPageHarness(tester);
    await talking(harness);
    await harness.minimize();

    showCallScreen(harness.navigatorKey.currentState!, harness.call);
    showCallScreen(harness.navigatorKey.currentState!, harness.call);
    await harness.settle();
    await tester.binding.handlePopRoute();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
    await harness.close();
  });

  testWidgets('a call that ends while minimized gives back the notice, the '
      'wakelock and its video', (tester) async {
    final harness = CallPageHarness(tester);
    final session = await talking(
      harness,
      kind: CallKind.video,
      remoteCamera: true,
    );
    await harness.minimize();

    session.end();
    await harness.settle();

    expect(harness.count('stopCallForegroundService'), 1);
    expect(harness.wakelockToggles, [true, false]);
    expect(harness.pictureInPictureEligible, isFalse);
    expect(harness.container.read(activeCallProvider), isNull);
    expect(
      harness.webrtc.where((c) => c.method == 'videoRendererDispose'),
      hasLength(
        harness.webrtc.where((c) => c.method == 'createVideoRenderer').length,
      ),
    );
    expect(
      harness.webrtc.where((c) => c.method == 'createVideoRenderer'),
      isNotEmpty,
    );
    await harness.close();
  });

  testWidgets('a failed call that ends while minimized says why', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    final session = await talking(harness);
    await harness.minimize();

    session.end(reason: CallEndReason.failed, message: 'Connection lost');
    await harness.settle();

    expect(find.text('Connection lost'), findsOneWidget);
  });

  testWidgets('tapping the ongoing-call notification returns to a minimized '
      'call', (tester) async {
    final harness = CallPageHarness(tester);
    await talking(harness);
    harness.container.read(callNotificationRouterProvider);
    await harness.minimize();

    harness.nativeEvents.add({'method': 'openCallScreen'});
    await CallNotificationService.instance.takeQueuedNativeCalls();
    await harness.settle();

    expect(find.byType(CallPage), findsOneWidget);
    await harness.close();
  });

  group('the call screen route', () {
    testWidgets('a call that ends while its screen slides away leaves the '
        'screen beneath alone', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness);
      await tester.tap(find.byTooltip('Minimize call'));
      await tester.pump(const Duration(milliseconds: 100));

      session.end();
      await harness.settle();

      expect(find.text('Chat'), findsOneWidget);
      expect(find.byType(CallPage), findsNothing);
    });

    testWidgets('reopening the call mid-slide and then ending it keeps the '
        'screen beneath', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness);
      await tester.tap(find.byTooltip('Minimize call'));
      await tester.pump(const Duration(milliseconds: 100));
      showCallScreen(harness.navigatorKey.currentState!, harness.call);
      await tester.pump(const Duration(milliseconds: 100));

      session.end();
      await harness.settle();

      expect(find.text('Chat'), findsOneWidget);
      expect(find.byType(CallPage), findsNothing);
    });

    testWidgets('a call that ends before its screen is ever drawn closes the '
        'screen and releases its video with no frame', (tester) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      await harness.showChat();
      final session = FakeCallSession(
        room: CallPageHarness.buildRoom(),
        kind: CallKind.video,
      );
      harness.pushCall(session);
      session.engine.participants = [
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ];
      session.moveTo(CallSessionPhase.active);
      for (var i = 0; i < 5; i++) {
        await tester.idle();
      }
      expect(
        harness.webrtc.where((c) => c.method == 'createVideoRenderer'),
        hasLength(2),
      );

      session.end();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.idle();
      }

      expect(
        harness.webrtc.where((c) => c.method == 'videoRendererDispose'),
        hasLength(2),
      );
      expect(harness.navigatorKey.currentState!.canPop(), isFalse);
    });

    testWidgets('a page opened from outside replaces the call screen, which '
        'minimizes to the bar', (tester) async {
      final harness = CallPageHarness(tester);
      await talking(harness);

      pushOverCallScreen(
        harness.navigatorKey.currentState!,
        harness.call,
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Elsewhere')),
        ),
      );
      await harness.settle();

      expect(find.text('Elsewhere'), findsOneWidget);
      expect(find.text('Return to call'), findsOneWidget);
      expect(harness.proximityScreenOff, isFalse);
      expect(harness.showOverLockscreen, isFalse);

      await tester.binding.handlePopRoute();
      await harness.settle();
      expect(find.text('Chat'), findsOneWidget);
      expect(find.byType(CallPage), findsNothing);
      await harness.close();
    });

    testWidgets('a call that ends under a page opened from outside leaves '
        'that page in place', (tester) async {
      final harness = CallPageHarness(tester);
      final session = await talking(harness);
      pushOverCallScreen(
        harness.navigatorKey.currentState!,
        harness.call,
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Elsewhere')),
        ),
      );
      await harness.settle();

      session.end();
      await harness.settle();

      expect(find.text('Elsewhere'), findsOneWidget);
    });
  });
}
