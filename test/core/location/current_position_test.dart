import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:zuno/core/location/current_position.dart';
import 'package:zuno/core/location/geo_uri.dart';

import '../../helpers/fake_geolocator.dart';

void main() {
  late FakeGeolocator geolocator;

  setUp(() => geolocator = FakeGeolocator());

  test('returns the fix as a geo URI with its accuracy', () async {
    final fix = await findCurrentLocation(geolocator: geolocator);

    expect(
      fix,
      LocationFound(
        geo: const GeoUri(
          latitude: 52.5163,
          longitude: 13.3777,
          uncertaintyMeters: 25,
        ),
        approximate: false,
        at: DateTime.utc(2026, 10, 7, 12),
      ),
    );
    expect(geolocator.permissionRequests, 0);
  });

  test('flags a coarse-only grant as approximate', () async {
    geolocator.accuracy = LocationAccuracyStatus.reduced;

    final fix = await findCurrentLocation(geolocator: geolocator);

    expect((fix as LocationFound).approximate, isTrue);
  });

  test('asks once when permission has not been decided yet', () async {
    geolocator
      ..permission = LocationPermission.denied
      ..afterRequest = LocationPermission.whileInUse;

    final fix = await findCurrentLocation(geolocator: geolocator);

    expect(fix, isA<LocationFound>());
    expect(geolocator.permissionRequests, 1);
  });

  test(
    'reports location services being off without asking for permission',
    () async {
      geolocator.servicesEnabled = false;

      final fix = await findCurrentLocation(geolocator: geolocator);

      expect(fix, const LocationFailed(LocationFailure.servicesOff));
      expect(geolocator.permissionRequests, 0);
    },
  );

  test('reports a refusal', () async {
    geolocator
      ..permission = LocationPermission.denied
      ..afterRequest = LocationPermission.denied;

    expect(
      await findCurrentLocation(geolocator: geolocator),
      const LocationFailed(LocationFailure.denied),
    );
  });

  test('reports a permanent refusal so the UI can route to settings', () async {
    geolocator.permission = LocationPermission.deniedForever;

    expect(
      await findCurrentLocation(geolocator: geolocator),
      const LocationFailed(LocationFailure.deniedForever),
    );
    expect(geolocator.permissionRequests, 0);
  });

  test('reports a fix that never arrived as unavailable', () async {
    geolocator.positionError = const LocationServiceDisabledException();

    expect(
      await findCurrentLocation(geolocator: geolocator),
      const LocationFailed(LocationFailure.unavailable),
    );
  });

  group('watching this device\'s own location', () {
    test('streams every fix, without background updates', () async {
      final fixes = <LocationFix>[];
      final updates = watchOwnLocation(geolocator: geolocator)
          .listen(fixes.add);
      await pumpEventQueue();

      geolocator.positions.add(fakePosition(latitude: 52.52, accuracy: 8));
      await pumpEventQueue();

      expect(fixes.single, isA<LocationFound>());
      expect((fixes.single as LocationFound).geo.latitude, 52.52);
      expect((fixes.single as LocationFound).geo.uncertaintyMeters, 8);
      expect(geolocator.streamSettings.single.runtimeType, LocationSettings);
      await updates.cancel();
      expect(geolocator.streaming, isFalse);
    });

    test('asks for permission first, and stops at a refusal', () async {
      geolocator
        ..permission = LocationPermission.denied
        ..afterRequest = LocationPermission.denied;

      final fixes = await watchOwnLocation(geolocator: geolocator).toList();

      expect(fixes, [const LocationFailed(LocationFailure.denied)]);
      expect(geolocator.permissionRequests, 1);
      expect(geolocator.streamSettings, isEmpty);
    });

    test('says so when location services are off', () async {
      geolocator.servicesEnabled = false;

      final fixes = await watchOwnLocation(geolocator: geolocator).toList();

      expect(fixes, [const LocationFailed(LocationFailure.servicesOff)]);
    });

    test('reads services turned off mid-stream as such', () async {
      final fixes = <LocationFix>[];
      final updates = watchOwnLocation(geolocator: geolocator)
          .listen(fixes.add);
      await pumpEventQueue();

      geolocator.positions.addError(const LocationServiceDisabledException());
      await pumpEventQueue();

      expect(fixes, [const LocationFailed(LocationFailure.servicesOff)]);
      await updates.cancel();
    });
  });
}
