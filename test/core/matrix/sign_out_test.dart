import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/matrix/sign_out.dart';

import '../../helpers/fake_live_location.dart';

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
      liveLocation: sharing,
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
      liveLocation: sharing,
      stopDelivery: (_) async {},
    );

    expect(client.journal.last, 'logged out');
  });
}
