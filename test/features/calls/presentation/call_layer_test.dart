import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/core/ui/sheet.dart';
import 'package:zuno/features/calls/presentation/call_bar.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';
import 'package:zuno/features/calls/presentation/call_status_line.dart';
import 'package:zuno/features/calls/presentation/call_window.dart';
import 'package:zuno/features/calls/presentation/participant_tile.dart';

import 'call_page_harness.dart';

void main() {
  Future<FakeCallSession> call(
    CallPageHarness harness, {
    bool remoteCamera = false,
    bool muted = false,
    CallSessionRole role = CallSessionRole.callee,
    bool answered = true,
  }) async {
    final session = FakeCallSession(
      room: CallPageHarness.buildRoom(),
      kind: remoteCamera ? CallKind.video : CallKind.voice,
      role: role,
    );
    await harness.open(session);
    if (answered) {
      session.engine.participants = [
        localParticipant(muted: muted),
        remoteParticipant(camera: remoteCamera),
      ];
      session.moveTo(CallSessionPhase.active);
      await harness.settle();
    }
    return session;
  }

  testWidgets('nothing shows while the call screen is open', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness);

    expect(find.byType(CallBar), findsNothing);
    expect(find.byType(CallWindow), findsNothing);
    await harness.close();
  });

  testWidgets('a minimized voice call is a bar above the app, which moves '
      'down for it', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness);
    await harness.minimize();

    expect(find.text('Return to call'), findsOneWidget);
    expect(find.text('Weekend hike'), findsOneWidget);
    expect(find.byType(CallWindow), findsNothing);
    expect(
      tester.getTopLeft(find.text('Chat')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(CallBar)).dy),
    );
    await harness.close();
  });

  testWidgets('the bar says what an unanswered call is doing', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness, role: CallSessionRole.caller, answered: false);
    await harness.minimize();

    expect(find.text('Calling…'), findsOneWidget);
    await harness.close();
  });

  testWidgets('a minimized call whose keys have not arrived says so on the '
      'bar, without a timer', (tester) async {
    final harness = CallPageHarness(tester);
    final session = await call(harness);
    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(encrypted: false),
    ]);
    await harness.settle();
    await harness.minimize();

    expect(
      find.descendant(
        of: find.byType(CallBar),
        matching: find.text('Encrypting…'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(CallBar),
        matching: find.byType(CallTimer),
      ),
      findsNothing,
    );
    await harness.close();
  });

  testWidgets('the bar shows when you are muted', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness, muted: true);
    await harness.minimize();

    expect(
      find.descendant(
        of: find.byType(CallBar),
        matching: find.byIcon(Icons.mic_off_outlined),
      ),
      findsOneWidget,
    );
    await harness.close();
  });

  testWidgets('with the other camera on, the call floats as a window', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    await call(harness, remoteCamera: true);
    await harness.minimize();

    expect(find.byType(CallWindow), findsOneWidget);
    expect(find.byType(ParticipantTile), findsOneWidget);
    expect(find.byType(CallBar), findsNothing);
    await harness.close();
  });

  testWidgets('the bar and the window swap as the camera goes on and off', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    final session = await call(harness);
    await harness.minimize();

    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(camera: true),
    ]);
    await harness.settle();
    expect(find.byType(CallWindow), findsOneWidget);
    expect(find.byType(CallBar), findsNothing);

    session.engine.setParticipants([localParticipant(), remoteParticipant()]);
    await harness.settle();
    expect(find.byType(CallWindow), findsNothing);
    expect(find.byType(CallBar), findsOneWidget);
    await harness.close();
  });

  for (final (name, surface, remoteCamera) in [
    ('bar', CallBar, false),
    ('window', CallWindow, true),
  ]) {
    testWidgets('tapping the $name returns to the call', (tester) async {
      final harness = CallPageHarness(tester);
      await call(harness, remoteCamera: remoteCamera);
      await harness.minimize();

      await tester.tap(find.byType(surface));
      await harness.settle();

      expect(find.byType(CallPage), findsOneWidget);
      expect(find.byType(surface), findsNothing);
      await harness.close();
    });
  }

  testWidgets('the bar leaves once the call ends', (tester) async {
    final harness = CallPageHarness(tester);
    final session = await call(harness);
    await harness.minimize();

    session.end();
    await harness.settle();

    expect(find.byType(CallBar), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('the window snaps to the nearest corner and keeps it when the '
      'call is reopened and minimized again', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness, remoteCamera: true);
    await harness.minimize();
    expect(tester.getTopLeft(find.byType(CallWindow)), const Offset(244, 64));

    await tester.drag(find.byType(CallWindow), const Offset(-200, 400));
    await harness.settle();
    expect(tester.getTopLeft(find.byType(CallWindow)), const Offset(8, 488));

    await tester.tap(find.byType(CallWindow));
    await harness.settle();
    await harness.minimize();
    expect(tester.getTopLeft(find.byType(CallWindow)), const Offset(8, 488));
    await harness.close();
  });

  testWidgets('the window rides above the keyboard frame by frame', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    await call(harness, remoteCamera: true);
    await harness.minimize();
    await tester.drag(find.byType(CallWindow), const Offset(-200, 400));
    await harness.settle();

    for (final inset in [100.0, 200.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getBottomLeft(find.byType(CallWindow)).dy, 640 - inset - 8);
    }
    await harness.close();
  });

  Future<void> toBottomLeft(CallPageHarness harness) async {
    await harness.tester.drag(find.byType(CallWindow), const Offset(-200, 400));
    await harness.settle();
  }

  testWidgets('the window keeps clear of the bottom bar', (tester) async {
    final harness = CallPageHarness(
      tester,
      home: const Scaffold(
        body: Text('Chat'),
        bottomNavigationBar: KeepClearArea(child: SizedBox(height: 80)),
      ),
    );
    await call(harness, remoteCamera: true);
    await harness.minimize();
    await toBottomLeft(harness);

    expect(tester.getBottomLeft(find.byType(CallWindow)).dy, 640 - 80 - 8);
    await harness.close();
  });

  testWidgets('the window rides above the composer and the keyboard '
      'together, frame by frame', (tester) async {
    final harness = CallPageHarness(
      tester,
      home: const Scaffold(
        body: Column(
          children: [
            Expanded(child: Text('Chat')),
            KeepClearArea(child: SizedBox(height: 60)),
          ],
        ),
      ),
    );
    await call(harness, remoteCamera: true);
    await harness.minimize();
    await toBottomLeft(harness);

    for (final inset in [100.0, 200.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getBottomLeft(find.byType(CallWindow)).dy,
        640 - inset - 60 - 8,
      );
    }
    await harness.close();
  });

  testWidgets('a bar on a page now covered by another page no longer holds '
      'the window up', (tester) async {
    final harness = CallPageHarness(
      tester,
      home: const Scaffold(
        body: Text('Chat'),
        bottomNavigationBar: KeepClearArea(child: SizedBox(height: 80)),
      ),
    );
    await call(harness, remoteCamera: true);
    await harness.minimize();
    await toBottomLeft(harness);

    unawaited(
      harness.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Settings')),
        ),
      ),
    );
    await harness.settle();
    await tester.pump();

    expect(tester.getBottomLeft(find.byType(CallWindow)).dy, 640 - 8);
    await harness.close();
  });

  testWidgets('a sheet pushes the window above the whole sheet, handle and '
      'all, while it is open', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness, remoteCamera: true);
    await harness.minimize();
    await toBottomLeft(harness);

    unawaited(
      showSheet<void>(
        context: tester.element(find.text('Chat')),
        builder: (_) => const SizedBox(height: 200),
      ),
    );
    await harness.settle();
    await tester.pump();
    expect(
      tester.getBottomLeft(find.byType(CallWindow)).dy,
      tester.getRect(find.byType(BottomSheet)).top - 8,
    );
    expect(tester.getRect(find.byType(BottomSheet)).top, lessThan(640 - 200));

    harness.navigatorKey.currentState!.pop();
    await harness.settle();
    await tester.pump();
    expect(tester.getBottomLeft(find.byType(CallWindow)).dy, 640 - 8);
    await harness.close();
  });

  testWidgets('the window starts below every top banner', (tester) async {
    final harness = CallPageHarness(
      tester,
      topBanner: const SizedBox(height: 40),
    );
    await call(harness, remoteCamera: true);
    await harness.minimize();

    expect(tester.getTopLeft(find.byType(CallWindow)), const Offset(244, 104));
    await harness.close();
  });

  testWidgets('minimizing grows the bar with the slide instead of in one '
      'frame', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness);

    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final barHeight = tester.getSize(find.byType(CallBar)).height;
    expect(tester.getTopLeft(find.text('Chat')).dy, lessThan(barHeight));

    await harness.settle();
    expect(tester.getTopLeft(find.text('Chat')).dy, barHeight);
    await harness.close();
  });

  testWidgets('screen readers find the bar and the window as buttons that '
      'return to the call', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = CallPageHarness(tester);
    final session = await call(harness);
    await harness.minimize();

    for (final surface in [CallBar, CallWindow]) {
      if (surface == CallWindow) {
        session.engine.setParticipants([
          localParticipant(),
          remoteParticipant(camera: true),
        ]);
        await harness.settle();
      }
      expect(
        tester.getSemantics(find.byType(surface)),
        isSemantics(
          label: 'Return to call',
          isButton: true,
          hasTapAction: true,
          size: tester.getSize(find.byType(surface)),
        ),
      );
    }
    await harness.close();
    semantics.dispose();
  });

  testWidgets('android picture-in-picture shows only the other side, even '
      'from a chat', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness, remoteCamera: true);
    await harness.minimize();

    CallNotificationService.instance.inPictureInPicture.value = true;
    await harness.settle();

    expect(find.byType(ParticipantTile), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    expect(find.byType(CallWindow), findsNothing);

    CallNotificationService.instance.inPictureInPicture.value = false;
    await harness.settle();

    expect(find.text('Chat'), findsOneWidget);
    expect(find.byType(CallWindow), findsOneWidget);
    await harness.close();
  });

  testWidgets('android picture-in-picture over the call screen hides its '
      'controls', (tester) async {
    final harness = CallPageHarness(tester);
    await call(harness, remoteCamera: true);

    CallNotificationService.instance.inPictureInPicture.value = true;
    await harness.settle();

    expect(find.byType(ParticipantTile), findsOneWidget);
    expect(find.byTooltip('End call'), findsNothing);
    await harness.close();
  });
}
