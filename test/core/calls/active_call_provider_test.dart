import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_marker.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;
  late ProviderContainer container;

  setUp(() {
    room = buildTestRoom(Client('test', database: FakeDatabaseApi()));
    markCallActiveInProcess(false);
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  ActiveCallNotifier line() => container.read(activeCallProvider.notifier);

  CallSession session() =>
      CallSession.forIncoming(room: room, callId: 'c1', kind: CallKind.voice);

  FakeCallSession fakeCall() =>
      FakeCallSession(room: room, kind: CallKind.voice);

  test('a live call is marked for the whole process', () {
    line().set(session());

    expect(isCallActiveInProcess(), isTrue);
  });

  test('clearing the call that is live ends it, disposes it and drops the '
      'mark', () {
    final live = fakeCall();
    line().start(() => live);

    line().clear(live);

    expect(container.read(activeCallProvider), isNull);
    expect(live.disposed, isTrue);
    expect(isCallActiveInProcess(), isFalse);
  });

  test('clearing a call that is no longer live leaves the newer call alone '
      'and disposes nothing', () {
    final ended = fakeCall();
    final newer = fakeCall();
    line().set(newer);

    line().clear(ended);

    expect(container.read(activeCallProvider), same(newer));
    expect(ended.disposed, isFalse);
    expect(newer.disposed, isFalse);
    expect(isCallActiveInProcess(), isTrue);
  });

  group('starting a call', () {
    test('a live call refuses another, which is never built', () {
      final live = session();
      expect(line().start(() => live), same(live));

      var built = false;
      final refused = line().start(() {
        built = true;
        return session();
      });

      expect(refused, isNull);
      expect(built, isFalse);
      expect(container.read(activeCallProvider), same(live));
    });

    test('a call that has ended no longer holds the line', () {
      line().start(() => fakeCall()..end());
      final next = session();

      expect(line().start(() => next), same(next));
      expect(isCallActiveInProcess(), isTrue);
    });

    test('a cleared call lets the next one start', () {
      final first = session();
      line().start(() => first);
      line().clear(first);
      final next = session();

      expect(line().start(() => next), same(next));
    });
  });

  group('answering a ringing call', () {
    late ProviderContainer answering;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      answering = ProviderContainer(
        overrides: [
          matrixClientProvider.overrideWithValue(room.client),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(answering.dispose);
      RingingCall.instance.set('c1');
      addTearDown(() => RingingCall.instance.callId = null);
    });

    IncomingCall ringing(String callId) => IncomingCall(
      room: room,
      callId: callId,
      callerId: '@bob:example.org',
      kind: CallKind.video,
    );

    test('starts it as the callee, settles it and takes back its ring '
        'screen\'s claim', () {
      final answered = answering
          .read(activeCallProvider.notifier)
          .answer(ringing('c1'));

      expect(answered?.callId, 'c1');
      expect(answered?.role, CallSessionRole.callee);
      expect(answered?.kind, CallKind.video);
      expect(answering.read(activeCallProvider), same(answered));
      expect(answering.read(resolvedCallIdsProvider), {'c1'});
      expect(RingingCall.instance.callId, isNull);
    });

    test('while another call is on settles nothing', () {
      final live = fakeCall();
      answering.read(activeCallProvider.notifier).start(() => live);

      expect(
        answering.read(activeCallProvider.notifier).answer(ringing('c1')),
        isNull,
      );
      expect(answering.read(activeCallProvider), same(live));
      expect(answering.read(resolvedCallIdsProvider), isEmpty);
      expect(RingingCall.instance.callId, 'c1');
    });
  });

  group('letting go of a call', () {
    test('a call replaced by the next is disposed, the next one is not', () {
      final first = fakeCall()..end();
      final second = fakeCall();

      line().start(() => first);
      line().start(() => second);

      expect(first.disposed, isTrue);
      expect(second.disposed, isFalse);
    });

    test('the call on the line when the app shuts down is disposed', () {
      final live = fakeCall();
      line().start(() => live);

      container.dispose();

      expect(live.disposed, isTrue);
    });
  });

  test('a mark left by an earlier run is dropped on start', () {
    markCallActiveInProcess(true);

    container.read(activeCallProvider);

    expect(isCallActiveInProcess(), isFalse);
  });
}
