import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../errors/caught_errors.dart';
import 'geo_uri.dart';

sealed class LocationFix {
  const LocationFix();
}

class LocationFound extends LocationFix {
  final GeoUri geo;
  final bool approximate;
  final DateTime at;

  const LocationFound({
    required this.geo,
    required this.approximate,
    required this.at,
  });

  @override
  bool operator ==(Object other) =>
      other is LocationFound &&
      other.geo == geo &&
      other.approximate == approximate &&
      other.at == at;

  @override
  int get hashCode => Object.hash(geo, approximate, at);
}

enum LocationFailure { servicesOff, denied, deniedForever, unavailable }

class LocationFailed extends LocationFix {
  final LocationFailure reason;

  const LocationFailed(this.reason);

  @override
  bool operator ==(Object other) =>
      other is LocationFailed && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

const _ownLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10,
);

Future<LocationFix> findCurrentLocation({
  GeolocatorPlatform? geolocator,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final platform = geolocator ?? GeolocatorPlatform.instance;
  try {
    final refusal = await _access(platform);
    if (refusal != null) return refusal;
    final position = await platform.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return _found(position, approximate: await _isApproximate(platform));
  } catch (error, stack) {
    if (error is! TimeoutException && !_isAccessLost(error)) {
      reportCaughtType('find current location', error, stack);
    }
    return const LocationFailed(LocationFailure.unavailable);
  }
}

Stream<LocationFix> watchOwnLocation({GeolocatorPlatform? geolocator}) async* {
  final platform = geolocator ?? GeolocatorPlatform.instance;
  final LocationFailed? refusal;
  try {
    refusal = await _access(platform);
  } catch (error, stack) {
    reportCaughtType('watch location access', error, stack);
    yield const LocationFailed(LocationFailure.unavailable);
    return;
  }
  if (refusal != null) {
    yield refusal;
    return;
  }
  final approximate = await _isApproximate(platform);
  yield* platform
      .getPositionStream(locationSettings: _ownLocationSettings)
      .map<LocationFix>(
        (position) => _found(position, approximate: approximate),
      )
      .transform(
        StreamTransformer<LocationFix, LocationFix>.fromHandlers(
          handleError: (error, stack, sink) {
            if (!_isAccessLost(error)) {
              reportCaughtType('watch location', error, stack);
            }
            sink.add(
              LocationFailed(
                error is LocationServiceDisabledException
                    ? LocationFailure.servicesOff
                    : LocationFailure.unavailable,
              ),
            );
          },
        ),
      );
}

bool _isAccessLost(Object error) =>
    error is LocationServiceDisabledException ||
    error is PermissionDeniedException;

Future<LocationFailed?> _access(GeolocatorPlatform platform) async {
  if (!await platform.isLocationServiceEnabled()) {
    return const LocationFailed(LocationFailure.servicesOff);
  }
  var permission = await platform.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await platform.requestPermission();
  }
  return switch (permission) {
    LocationPermission.deniedForever => const LocationFailed(
      LocationFailure.deniedForever,
    ),
    LocationPermission.denied || LocationPermission.unableToDetermine =>
      const LocationFailed(LocationFailure.denied),
    LocationPermission.whileInUse || LocationPermission.always => null,
  };
}

LocationFound _found(Position position, {required bool approximate}) =>
    LocationFound(
      geo: GeoUri(
        latitude: position.latitude,
        longitude: position.longitude,
        uncertaintyMeters: position.accuracy > 0 ? position.accuracy : null,
      ),
      approximate: approximate,
      at: position.timestamp,
    );

Future<bool> _isApproximate(GeolocatorPlatform platform) async {
  try {
    return await platform.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced;
  } catch (error, stack) {
    reportCaughtType('location accuracy', error, stack);
    return false;
  }
}
