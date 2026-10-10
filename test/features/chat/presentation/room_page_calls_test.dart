import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/call_channel_mocks.dart';
import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_call_session.dart';
import '../../../helpers/fake_matrix.dart';
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
      joinCall(
        harness.room,
        userId: '@bob:example.org',
        deviceId: 'BOBPHONE',
        callId: callInProgress,
        kind: callKind,
        expiresIn: const Duration(minutes: 5),
      );
    }
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    status.add(ConnectionStatus.online);
    await harness.settle(tester);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(RoomPage)));

  void alreadyInCall(WidgetTester tester, {Room? room}) => container(tester)
      .read(activeCallProvider.notifier)
      .set(FakeCallSession(room: room ?? harness.room, kind: CallKind.voice));

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
      alreadyInCall(
        tester,
        room: buildTestRoom(harness.room.client, id: '!other:example.org'),
      );

      await tester.tap(find.byTooltip('Voice call'));
      await harness.settle(tester);

      expect(find.text('You are already in a call'), findsOneWidget);
      expect(find.text('Call Hikers?'), findsNothing);
    });

    testWidgets('in the room of the call you are in, it returns to that call', (
      tester,
    ) async {
      CallChannelMocks();
      await openRoom(tester);
      alreadyInCall(tester);

      await tester.tap(find.byTooltip('Voice call'));
      await harness.settle(tester);

      expect(find.byType(CallPage), findsOneWidget);
      expect(find.text('You are already in a call'), findsNothing);
      expect(find.text('Call Hikers?'), findsNothing);
    });

    testWidgets('a prompt confirmed while another call went on underneath '
        'leaves that call alone', (tester) async {
      await openRoom(tester);
      await tester.tap(find.byTooltip('Voice call'));
      await harness.settle(tester);
      expect(find.text('Call Hikers?'), findsOneWidget);
      final other = FakeCallSession(
        room: buildTestRoom(harness.room.client, id: '!other:example.org'),
        kind: CallKind.voice,
      );
      container(tester).read(activeCallProvider.notifier).set(other);

      await tester.tap(find.widgetWithText(TextButton, 'Call'));
      await harness.settle(tester);

      expect(find.text('You are already in a call'), findsOneWidget);
      expect(container(tester).read(activeCallProvider), same(other));
      expect(other.hangUps, 0);
    });

    testWidgets('a prompt confirmed while a call in this room went on '
        'underneath returns to that call', (tester) async {
      CallChannelMocks();
      await openRoom(tester);
      await tester.tap(find.byTooltip('Voice call'));
      await harness.settle(tester);
      alreadyInCall(tester);
      final scope = container(tester);
      final live = scope.read(activeCallProvider);

      await tester.tap(find.widgetWithText(TextButton, 'Call'));
      await harness.settle(tester);

      expect(find.byType(CallPage), findsOneWidget);
      expect(scope.read(activeCallProvider), same(live));
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

    testWidgets('joining during a call in another room says you are already '
        'in one', (tester) async {
      await openRoom(tester, callInProgress: 'c-bob');
      alreadyInCall(
        tester,
        room: buildTestRoom(harness.room.client, id: '!other:example.org'),
      );
      await harness.settle(tester);

      await tester.tap(find.text('Voice call in progress'));
      await harness.settle(tester);

      expect(container(tester).read(activeCallProvider)!.callId, 'call-1');
      expect(find.text('You are already in a call'), findsOneWidget);
    });

    testWidgets('joining in the room of the call you are in returns to that '
        'call', (tester) async {
      CallChannelMocks();
      await openRoom(tester, callInProgress: 'c-bob');
      alreadyInCall(tester);
      await harness.settle(tester);
      final scope = container(tester);

      await tester.tap(find.text('Voice call in progress'));
      await harness.settle(tester);

      expect(find.byType(CallPage), findsOneWidget);
      expect(find.text('You are already in a call'), findsNothing);
      expect(scope.read(activeCallProvider)!.callId, 'call-1');
    });

    testWidgets('the call you are in gets no banner', (tester) async {
      await openRoom(tester, callInProgress: 'call-1');
      alreadyInCall(tester);
      await harness.settle(tester);

      expect(find.text('Voice call in progress'), findsNothing);
    });
  });
}
