import 'package:geolocator/geolocator.dart';

import 'geo_uri.dart';

sealed class LocationFix {
  const LocationFix();
}

class LocationFound extends LocationFix {
  final GeoUri geo;
  final bool approximate;

  const LocationFound({required this.geo, required this.approximate});

  @override
  bool operator ==(Object other) =>
      other is LocationFound &&
      other.geo == geo &&
      other.approximate == approximate;

  @override
  int get hashCode => Object.hash(geo, approximate);
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

Future<LocationFix> findCurrentLocation({
  GeolocatorPlatform? geolocator,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final platform = geolocator ?? GeolocatorPlatform.instance;
  try {
    if (!await platform.isLocationServiceEnabled()) {
      return const LocationFailed(LocationFailure.servicesOff);
    }
    var permission = await platform.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await platform.requestPermission();
    }
    switch (permission) {
      case LocationPermission.deniedForever:
        return const LocationFailed(LocationFailure.deniedForever);
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return const LocationFailed(LocationFailure.denied);
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }
    final position = await platform.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return LocationFound(
      geo: GeoUri(
        latitude: position.latitude,
        longitude: position.longitude,
        uncertaintyMeters: position.accuracy > 0 ? position.accuracy : null,
      ),
      approximate: await _isApproximate(platform),
    );
  } catch (_) {
    return const LocationFailed(LocationFailure.unavailable);
  }
}

Future<bool> _isApproximate(GeolocatorPlatform platform) async {
  try {
    return await platform.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced;
  } catch (_) {
    return false;
  }
}
