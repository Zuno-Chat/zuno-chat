import 'dart:async';

import 'package:geolocator/geolocator.dart';

Position fakePosition({
  double latitude = 52.5163,
  double longitude = 13.3777,
  double accuracy = 25,
  DateTime? at,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: at ?? DateTime.utc(2026, 10, 7, 12),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeGeolocator extends GeolocatorPlatform {
  bool servicesEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  Position position = fakePosition();
  Object? positionError;
  int permissionRequests = 0;
  final positions = StreamController<Position>.broadcast();
  final streamSettings = <LocationSettings?>[];

  bool get streaming => positions.hasListener;

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
    return position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamSettings.add(locationSettings);
    return positions.stream;
  }
}
