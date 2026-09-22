import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:zuno/core/location/current_position.dart';
import 'package:zuno/core/location/geo_uri.dart';

class _FakeGeolocator extends GeolocatorPlatform {
  bool servicesEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  Object? positionError;
  int permissionRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => servicesEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission = afterRequest;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracy;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final error = positionError;
    if (error != null) throw error;
    return Position(
      latitude: 52.5163,
      longitude: 13.3777,
      timestamp: DateTime.now(),
      accuracy: 25,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late _FakeGeolocator geolocator;

  setUp(() => geolocator = _FakeGeolocator());

  test('returns the fix as a geo URI with its accuracy', () async {
    final fix = await findCurrentLocation(geolocator: geolocator);

    expect(
      fix,
      const LocationFound(
        geo: GeoUri(
          latitude: 52.5163,
          longitude: 13.3777,
          uncertaintyMeters: 25,
        ),
        approximate: false,
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
}
