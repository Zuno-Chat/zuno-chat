import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/module/calls_module.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/fake_matrix.dart';
import 'call_page_harness.dart';

const _me = '@me:example.org';
const _ann = '@ann:example.org';
const _bob = '@bob:example.org';

Room _groupRoom({required int myLevel}) {
  final room = buildCallRoom();
  room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      senderId: _bob,
      stateKey: _bob,
      content: {'membership': 'join', 'displayname': 'Bob'},
    ),
  );
  setPowerLevels(room, {
    'users': {_me: myLevel},
  });
  return room;
}

List<CallEngineParticipant> _everyone({bool meMuted = false}) => [
  localParticipant(muted: meMuted),
  remoteParticipant(),
  remoteParticipant(userId: _bob),
];

void main() {
  Future<(CallPageHarness, FakeCallSession)> inGroupCall(
    WidgetTester tester, {
    int myLevel = 50,
    List<CallEngineParticipant>? remotes,
  }) async {
    final harness = CallPageHarness(tester);
    final session = FakeCallSession(
      room: _groupRoom(myLevel: myLevel),
      kind: CallKind.voice,
    );
    await harness.open(session);
    session.engine.participants = remotes == null
        ? _everyone()
        : [localParticipant(), ...remotes];
    session.moveTo(CallSessionPhase.active);
    await harness.settle();
    return (harness, session);
  }

  Future<void> holdAnn(CallPageHarness harness) async {
    await harness.tester.longPress(find.text('Ann'));
    await harness.settle();
  }

  Future<void> askToRemoveAnn(CallPageHarness harness) async {
    await holdAnn(harness);
    await harness.tester.tap(find.text('Remove from call'));
    await harness.settle();
  }

  testWidgets('someone in charge holds a person and mutes them', (
    tester,
  ) async {
    final (harness, session) = await inGroupCall(tester);

    await holdAnn(harness);
    expect(find.text('Remove from call'), findsOneWidget);
    await tester.tap(find.text('Mute'));
    await harness.settle();

    expect(session.mutedPeople, [_ann]);
    expect(find.text('Mute'), findsNothing);
    await harness.close();
  });

  testWidgets('holding your own tile opens nothing', (tester) async {
    final (harness, _) = await inGroupCall(tester);

    await tester.longPress(find.text('You'));
    await harness.settle();

    expect(find.text('Remove from call'), findsNothing);
    await harness.close();
  });

  testWidgets('a plain tap on a person opens nothing', (tester) async {
    final (harness, _) = await inGroupCall(tester);

    await tester.tap(find.text('Ann'));
    await harness.settle();

    expect(find.text('Remove from call'), findsNothing);
    await harness.close();
  });

  testWidgets('someone already muted is offered only removal', (tester) async {
    final (harness, _) = await inGroupCall(
      tester,
      remotes: [
        remoteParticipant(muted: true),
        remoteParticipant(userId: _bob),
      ],
    );

    await holdAnn(harness);

    expect(find.text('Remove from call'), findsOneWidget);
    expect(find.text('Mute'), findsNothing);
    await harness.close();
  });

  testWidgets('removing asks first, says what it means, and does nothing on '
      'cancel', (tester) async {
    final (harness, session) = await inGroupCall(tester);

    await askToRemoveAnn(harness);

    expect(find.text('Remove Ann from the call?'), findsOneWidget);
    expect(
      find.text(
        'They cannot rejoin this call. They stay in the room and can join '
        'the next call.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await harness.settle();

    expect(session.removedPeople, isEmpty);
    await harness.close();
  });

  testWidgets('a confirmed removal asks the call to remove them', (
    tester,
  ) async {
    final (harness, session) = await inGroupCall(tester);

    await askToRemoveAnn(harness);
    await tester.tap(find.text('Remove'));
    await harness.settle();

    expect(session.removedPeople, [_ann]);
    await harness.close();
  });

  testWidgets('a removal that fails says so', (tester) async {
    final (harness, session) = await inGroupCall(tester);
    session.moderationError = CallsModuleException(
      'HTTP 403 from POST /remove: M_FORBIDDEN',
      statusCode: 403,
    );

    await askToRemoveAnn(harness);
    await tester.tap(find.text('Remove'));
    await harness.settle();

    expect(find.text('Ann was not removed. Try again.'), findsOneWidget);
    await harness.close();
  });

  testWidgets('a person opens nothing for someone not in charge', (
    tester,
  ) async {
    final (harness, _) = await inGroupCall(tester, myLevel: 0);

    await holdAnn(harness);

    expect(find.text('Remove from call'), findsNothing);
    await harness.close();
  });

  testWidgets('with one other person, holding them opens the same options', (
    tester,
  ) async {
    final (harness, _) = await inGroupCall(
      tester,
      remotes: [remoteParticipant()],
    );

    await holdAnn(harness);

    expect(find.text('Remove from call'), findsOneWidget);
    await harness.close();
  });

  testWidgets('while muted by someone, the call names them until the '
      'microphone is back on', (tester) async {
    final (harness, session) = await inGroupCall(tester);

    await session.setMicrophoneMuted(true, by: _ann);
    session.engine.participants = _everyone(meMuted: true);
    await harness.settle();
    expect(find.text('Ann muted you'), findsOneWidget);

    await tester.tap(find.byTooltip('Unmute'));
    session.engine.participants = _everyone();
    await harness.settle();
    expect(find.text('Ann muted you'), findsNothing);
    await harness.close();
  });

  testWidgets('being removed says who did it once the screen closes', (
    tester,
  ) async {
    final (harness, session) = await inGroupCall(tester);

    session.removedBy = _ann;
    session.end(reason: CallEndReason.removed);
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(find.text('Ann removed you from the call.'), findsOneWidget);
  });
}
