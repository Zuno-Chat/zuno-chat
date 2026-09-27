import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../calls/presentation/call_page_harness.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late StreamController<ConnectionStatus> status;

  setUp(() {
    status = StreamController<ConnectionStatus>.broadcast();
    addTearDown(status.close);
  });

  Future<void> openRoom(
    WidgetTester tester, {
    String? callInProgress,
    String callKind = 'voice',
    List<Override> overrides = const [],
  }) async {
    harness = RoomPageHarness(
      overrides: [
        connectionStatusProvider.overrideWith((ref) => status.stream),
        ...overrides,
      ],
    );
    harness.room.setState(
      buildTestEvent(
        harness.room,
        eventId: r'$name',
        senderId: '@bob:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Hikers'},
      ),
    );
    if (callInProgress != null) {
      harness.room.setState(
        buildTestEvent(
          harness.room,
          eventId: r'$bob-call',
          senderId: '@bob:example.org',
          stateKey: '@bob:example.org',
          type: callMemberEventType,
          content: {
            'memberships': [
              RtcMembership(
                callId: callInProgress,
                deviceId: 'BOBPHONE',
                kind: callKind,
                expiresAtMs: DateTime.now()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch,
                createdAtMs: 0,
                fociActive: const {},
              ).toJson(),
            ],
          },
        ),
      );
    }
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    status.add(ConnectionStatus.online);
    await harness.settle(tester);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(RoomPage)));

  void alreadyInCall(WidgetTester tester) =>
      container(tester)
          .read(activeCallProvider.notifier)
          .set(FakeCallSession(room: harness.room, kind: CallKind.voice));

  group('starting a call', () {
    for (final (tooltip, line) in [
      ('Voice call', 'Start a voice call.'),
      ('Video call', 'Start a video call.'),
    ]) {
      testWidgets('$tooltip asks first, and Cancel starts nothing', (
        tester,
      ) async {
        await openRoom(tester);

        await tester.tap(find.byTooltip(tooltip));
        await harness.settle(tester);

        expect(find.text('Call Hikers?'), findsOneWidget);
        expect(find.text(line), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await harness.settle(tester);

        expect(container(tester).read(activeCallProvider), isNull);
      });
    }

    testWidgets('is refused during another call', (tester) async {
      await openRoom(tester);
      alreadyInCall(tester);

      await tester.tap(find.byTooltip('Voice call'));
      await harness.settle(tester);

      expect(find.text('You are already in a call'), findsOneWidget);
      expect(find.text('Call Hikers?'), findsNothing);
    });

    testWidgets('is refused offline', (tester) async {
      await openRoom(tester);
      status.add(ConnectionStatus.noInternet);
      await harness.settle(tester);

      await tester.tap(find.byTooltip('Video call'));
      await harness.settle(tester);

      expect(
        find.text('No connection. Try again once back online.'),
        findsOneWidget,
      );
    });
  });

  group('a call already going on', () {
    testWidgets('gets a banner to join it', (tester) async {
      await openRoom(tester, callInProgress: 'c-bob');

      expect(find.text('Voice call in progress'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
    });

    testWidgets('a video call says so', (tester) async {
      await openRoom(tester, callInProgress: 'c-bob', callKind: 'video');

      expect(find.text('Video call in progress'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(InkWell, 'Video call in progress'),
          matching: find.byIcon(Icons.videocam_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('joining offline is refused', (tester) async {
      await openRoom(tester, callInProgress: 'c-bob');
      status.add(ConnectionStatus.noInternet);
      await harness.settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await harness.settle(tester);

      expect(
        find.text('No connection. Try again once back online.'),
        findsOneWidget,
      );
      expect(container(tester).read(activeCallProvider), isNull);
    });

    testWidgets('joining during another call does nothing', (tester) async {
      await openRoom(tester, callInProgress: 'c-bob');
      alreadyInCall(tester);
      await harness.settle(tester);

      await tester.tap(find.text('Voice call in progress'));
      await harness.settle(tester);

      expect(container(tester).read(activeCallProvider)!.callId, 'call-1');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the call you are in gets no banner', (tester) async {
      await openRoom(tester, callInProgress: 'call-1');
      alreadyInCall(tester);
      await harness.settle(tester);

      expect(find.text('Voice call in progress'), findsNothing);
    });
  });
}
