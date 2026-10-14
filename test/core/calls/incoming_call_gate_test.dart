import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/incoming_call_gate.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/call_membership.dart';
import '../../helpers/fake_call_engine.dart';
import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/fake_permissions.dart';
import '../../helpers/recording_incoming_call_presenter.dart';
import '../../helpers/send_recording_room.dart';
import '../../helpers/sent_call_declines.dart';

void main() {
  late Client client;
  late Room room;
  late SharedPreferences prefs;
  late SentCallDeclines declines;
  late RecordingIncomingCallPresenter presenter;
  late List<String> memberPuts;

  setUp(() async {
    memberPuts = [];
    RingingCall.instance.callId = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    declines = SentCallDeclines();
    presenter = RecordingIncomingCallPresenter();
    client = buildTestClient(
      userId: '@me:example.org',
      deviceId: 'THISPHONE',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        declines.record(request);
        if (request.method == 'PUT' &&
            request.url.path.contains(callMemberEventType)) {
          memberPuts.add(request.body);
        }
        return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  Future<ProviderContainer> pumpGate(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        incomingCallPresenterProvider.overrideWithValue(presenter),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: const Scaffold(),
        ),
      ),
    );
    return container;
  }

  IncomingCall callFrom(
    String callId, {
    String callerId = '@carol:example.org',
    Room? inRoom,
  }) => IncomingCall(
    room: inRoom ?? room,
    callId: callId,
    callerId: callerId,
    kind: CallKind.voice,
  );

  Future<bool> admit(
    WidgetTester tester,
    ProviderContainer container,
    IncomingCall call, {
    bool systemRinging = false,
  }) async {
    final rings = await tester.runAsync(
      () => container
          .read(incomingCallGateProvider.notifier)
          .shouldRing(call, systemRinging: () => systemRinging),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    return rings!;
  }

  FakeCallSession onACall(
    ProviderContainer container, {
    CallSessionRole role = CallSessionRole.callee,
    Room? inRoom,
  }) {
    final session = FakeCallSession(
      room: inRoom ?? room,
      kind: CallKind.voice,
      role: role,
    );
    container.read(activeCallProvider.notifier).set(session);
    return session;
  }

  testWidgets('a fresh call rings', (tester) async {
    final container = await pumpGate(tester);
    final declined = declines.watch();

    expect(await admit(tester, container, callFrom('call1')), isTrue);

    expect(declined, isEmpty);
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  group('a call already settled is left alone, never declined', () {
    testWidgets('when it is resolved here', (tester) async {
      final container = await pumpGate(tester);
      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call1')), isFalse);

      expect(declined, isEmpty);
    });

    testWidgets('when another isolate resolved it', (tester) async {
      final container = await pumpGate(tester);
      await markCallResolvedOnDisk(prefs, 'call1');

      expect(await admit(tester, container, callFrom('call1')), isFalse);
    });

    testWidgets('when its ring screen already shows', (tester) async {
      final container = await pumpGate(tester);
      RingingCall.instance.set('call1');

      expect(await admit(tester, container, callFrom('call1')), isFalse);
    });

    testWidgets('when it is the call already answered here, even while '
        'another call would make this device busy', (tester) async {
      final container = await pumpGate(tester);
      final answered = onACall(container);
      SystemRing.instance.set(roomId: room.id, callId: 'other');
      final declined = declines.watch();

      expect(
        await admit(tester, container, callFrom(answered.callId)),
        isFalse,
      );

      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
      expect(container.read(activeCallProvider), same(answered));
      SystemRing.instance.clear('other');
    });
  });

  testWidgets('a call my other device answered never rings, and its ring '
      'ends as answered elsewhere', (tester) async {
    final container = await pumpGate(tester);
    onACall(container);
    joinCall(room, userId: '@me:example.org', deviceId: 'LAPTOP', callId: 'c2');
    final declined = declines.watch();

    expect(await admit(tester, container, callFrom('c2')), isFalse);

    expect(declined, isEmpty);
    expect(find.textContaining('Missed call'), findsNothing);
    expect(container.read(resolvedCallIdsProvider), contains('c2'));
    expect(presenter.ends, [
      (roomId: room.id, callId: 'c2', end: RingEnd.answeredElsewhere),
    ]);
  });

  group('a second call while busy is declined and announced as missed', () {
    testWidgets('while on a call', (tester) async {
      final container = await pumpGate(tester);
      final session = onACall(container);
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call2')), isFalse);

      expect(declined, ['call2']);
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(find.text('Missed call from Carol'), findsOneWidget);
      expect(container.read(activeCallProvider), same(session));
    });

    testWidgets('while another call rings', (tester) async {
      final container = await pumpGate(tester);
      SystemRing.instance.set(roomId: room.id, callId: 'ringing');
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call2')), isFalse);

      expect(declined, ['call2']);
      expect(find.text('Missed call from Carol'), findsOneWidget);
      expect(SystemRing.instance.ringing.value?.callId, 'ringing');
      SystemRing.instance.clear('ringing');
    });
  });

  testWidgets('a call the system already rings is never turned away as '
      'busy', (tester) async {
    final container = await pumpGate(tester);
    onACall(container);
    final declined = declines.watch();

    expect(
      await admit(tester, container, callFrom('call2'), systemRinging: true),
      isTrue,
    );

    expect(declined, isEmpty);
    expect(find.textContaining('Missed call'), findsNothing);
    expect(container.read(resolvedCallIdsProvider), isEmpty);
  });

  testWidgets('the call that already rings is not busy with itself', (
    tester,
  ) async {
    final container = await pumpGate(tester);
    SystemRing.instance.set(roomId: room.id, callId: 'call1');
    final declined = declines.watch();

    expect(await admit(tester, container, callFrom('call1')), isTrue);

    expect(declined, isEmpty);
    SystemRing.instance.clear('call1');
  });

  group('two people calling each other at once', () {
    testWidgets('the call with the lower id wins: mine is hung up and theirs '
        'answered, with nothing declined', (tester) async {
      installFakePermissions(onRequest: permissionDenied);
      final container = await pumpGate(tester);
      final mine = onACall(container, role: CallSessionRole.caller);
      final started = <CallSession>[];
      container.listen(activeCallProvider, (_, session) {
        if (session != null) started.add(session);
      });
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call-0')), isFalse);
      expect(mine.hangUpsByUser, [false]);
      expect(mine.hangUpsSummarized, [true]);
      expect(started, isEmpty);

      mine.end(reason: CallEndReason.missed);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final answered = started.single;
      addTearDown(answered.dispose);
      expect(answered.callId, 'call-0');
      expect(answered.role, CallSessionRole.callee);
      expect(container.read(resolvedCallIdsProvider), contains('call-0'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
    });

    testWidgets('the call given up for theirs posts no missed call, and still '
        'leaves', (tester) async {
      final permissions = installFakePermissions();
      final container = await pumpGate(tester);
      final shared = SendRecordingRoom(client: client);
      final mine = (await tester.runAsync(() async {
        final session = CallSession.startOutgoing(
          shared,
          CallKind.voice,
          engineBuilder: FakeCallEngine.new,
        );
        await session.phaseStream.firstWhere(
          (phase) => phase == CallSessionPhase.active,
        );
        return session;
      }))!;
      container.read(activeCallProvider.notifier).set(mine);
      permissions.onRequest = permissionDenied;
      memberPuts.clear();

      expect(
        await admit(tester, container, callFrom('0', inRoom: shared)),
        isFalse,
      );
      await tester.runAsync(pumpEventQueue);

      expect(mine.phase, CallSessionPhase.ended);
      expect(
        shared.sentEvents.where((e) => e['msgtype'] == callSummaryMsgtype),
        isEmpty,
      );
      expect(memberPuts.first, contains('"memberships":[]'));
    });

    testWidgets('mine wins with the lower id: theirs is ignored, neither '
        'declined nor announced, and mine keeps ringing', (tester) async {
      final container = await pumpGate(tester);
      final mine = onACall(container, role: CallSessionRole.caller);
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call-2')), isFalse);

      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
      expect(mine.hangUps, 0);
      expect(container.read(activeCallProvider), same(mine));
      expect(container.read(resolvedCallIdsProvider), isEmpty);
    });

    testWidgets('once my call was answered, theirs is just a second call', (
      tester,
    ) async {
      final container = await pumpGate(tester);
      final mine = onACall(container, role: CallSessionRole.caller)
        ..everHadRemote = true;
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call-0')), isFalse);

      expect(declined, ['call-0']);
      expect(mine.hangUps, 0);
    });

    testWidgets('my call in another room makes theirs just a second call', (
      tester,
    ) async {
      final container = await pumpGate(tester);
      final mine = onACall(
        container,
        role: CallSessionRole.caller,
        inRoom: buildTestRoom(client, id: '!elsewhere:example.org'),
      );
      final declined = declines.watch();

      expect(await admit(tester, container, callFrom('call-0')), isFalse);

      expect(declined, ['call-0']);
      expect(mine.hangUps, 0);
    });
  });
}
