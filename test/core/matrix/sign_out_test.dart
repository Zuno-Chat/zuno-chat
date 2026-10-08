import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/matrix/sign_out.dart';

import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_live_location.dart';

class _StuckCall extends FakeCallSession {
  _StuckCall() : super(room: buildCallRoom(), kind: CallKind.voice);

  @override
  Future<void> hangUp({bool byUser = false, bool summarized = false}) =>
      Completer<void>().future;
}

void main() {
  late LiveLocationTestClient client;
  late LiveLocationSharing sharing;

  setUp(() {
    client = LiveLocationTestClient();
    client.rooms.add(LiveLocationTestRoom(id: '!family:x', client: client));
    sharing = LiveLocationSharing(
      client: client,
      capture: FakeLiveLocationCapture(),
      isOffline: () => false,
      recipients: (_) async => const <DeviceKeys>[],
    );
  });

  tearDown(() => sharing.dispose());

  test('clears live shares and stops delivery before signing out', () async {
    await sharing.start(
      client.getRoomById('!family:x')!,
      LiveLocationDuration.hour,
      LivePosition(
        geo: const GeoUri(latitude: 1, longitude: 2),
        at: DateTime.now(),
      ),
    );

    await signOutThisDevice(
      client,
      windDown: () =>
          windDownBeforeSignOut(activeCall: null, liveLocation: sharing),
      stopDelivery: (_) async => client.journal.add('delivery stopped'),
    );

    expect(client.journal, [
      'share published',
      'share cleared',
      'delivery stopped',
      'logged out',
    ]);
  });

  test('signs out even when a share cannot be cleared', () async {
    await sharing.start(
      client.getRoomById('!family:x')!,
      LiveLocationDuration.hour,
      LivePosition(
        geo: const GeoUri(latitude: 1, longitude: 2),
        at: DateTime.now(),
      ),
    );
    client.stateWriteError = MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'no',
    });

    await signOutThisDevice(
      client,
      windDown: () =>
          windDownBeforeSignOut(activeCall: null, liveLocation: sharing),
      stopDelivery: (_) async {},
    );

    expect(client.journal.last, 'logged out');
  });

  test('ends the call first, as the user\'s own choice, then clears shares '
      'and signs out', () async {
    await sharing.start(
      client.getRoomById('!family:x')!,
      LiveLocationDuration.hour,
      LivePosition(
        geo: const GeoUri(latitude: 1, longitude: 2),
        at: DateTime.now(),
      ),
    );

    await signOutThisDevice(
      client,
      windDown: () => windDownBeforeSignOut(
        activeCall: FakeCallSession(
          room: buildCallRoom(),
          kind: CallKind.voice,
          journal: client.journal,
        ),
        liveLocation: sharing,
      ),
      stopDelivery: (_) async => client.journal.add('delivery stopped'),
    );

    expect(client.journal, [
      'share published',
      'call ended',
      'share cleared',
      'delivery stopped',
      'logged out',
    ]);
  });

  testWidgets('a call that never finishes ending does not hold up signing '
      'out', (tester) async {
    var signedOut = false;
    unawaited(
      signOutThisDevice(
        client,
        windDown: () => windDownBeforeSignOut(
          activeCall: _StuckCall(),
          liveLocation: sharing,
        ),
        stopDelivery: (_) async {},
      ).then((_) => signedOut = true),
    );

    await tester.pump(const Duration(seconds: 6));

    expect(signedOut, isTrue);
    expect(client.journal.last, 'logged out');
  });

  test('the wind-down looks at the call and the shares when it runs, not '
      'when it is handed out', () async {
    final container = ProviderContainer(
      overrides: [liveLocationSharingProvider.overrideWithValue(sharing)],
    );
    addTearDown(container.dispose);
    final windDown = container.read(signOutWindDownProvider);

    container
        .read(activeCallProvider.notifier)
        .set(
          FakeCallSession(
            room: buildCallRoom(),
            kind: CallKind.voice,
            journal: client.journal,
          ),
        );
    await sharing.start(
      client.getRoomById('!family:x')!,
      LiveLocationDuration.hour,
      LivePosition(
        geo: const GeoUri(latitude: 1, longitude: 2),
        at: DateTime.now(),
      ),
    );
    await windDown();

    expect(client.journal, ['share published', 'call ended', 'share cleared']);
  });
}
