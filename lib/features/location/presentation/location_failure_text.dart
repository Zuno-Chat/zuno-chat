import 'package:geolocator/geolocator.dart';

import '../../../core/location/current_position.dart';

typedef LocationFailureCopy = ({
  String message,
  Future<bool> Function()? openSettings,
});

LocationFailureCopy locationFailureCopy(
  LocationFailure reason, {
  required String goal,
  required bool servicesSettings,
}) => switch (reason) {
  LocationFailure.servicesOff when servicesSettings => (
    message: 'Location is off. Turn it on to $goal.',
    openSettings: Geolocator.openLocationSettings,
  ),
  LocationFailure.servicesOff => (
    message:
        'Location is off. Turn on Location Services in Settings, under '
        'Privacy & Security.',
    openSettings: null,
  ),
  LocationFailure.denied => (
    message: 'Allow location access to $goal.',
    openSettings: null,
  ),
  LocationFailure.deniedForever => (
    message: 'Location access is blocked. Allow it in Settings.',
    openSettings: Geolocator.openAppSettings,
  ),
  LocationFailure.unavailable => (
    message: 'Could not find your location.',
    openSettings: null,
  ),
};
