import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:zuno/core/location/current_position.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/location/presentation/location_failure_text.dart';

import '../../../helpers/platform_capabilities.dart';

void main() {
  const goal = 'share where you are';

  LocationFailureCopy copyOn(
    PlatformCapabilities capabilities,
    LocationFailure reason,
  ) => locationFailureCopy(
    reason,
    goal: goal,
    servicesSettings: capabilities.locationServicesSettings,
  );

  group('location services off', () {
    test('on Android, says to turn it on for the goal, and opens the location '
        'settings', () {
      final copy = copyOn(androidCapabilities, LocationFailure.servicesOff);

      expect(
        copy.message,
        'Location is off. Turn it on to share where you are.',
      );
      expect(copy.openSettings, Geolocator.openLocationSettings);
    });

    test(
      'on iOS, names the way to Location Services, with nothing to open',
      () {
        final copy = copyOn(iosCapabilities, LocationFailure.servicesOff);

        expect(
          copy.message,
          'Location is off. Turn on Location Services in Settings, under '
          'Privacy & Security.',
        );
        expect(copy.openSettings, isNull);
      },
    );
  });

  for (final (platform, capabilities) in [
    ('Android', androidCapabilities),
    ('iOS', iosCapabilities),
  ]) {
    group('on $platform', () {
      test('a refusal asks for access to reach the goal, with nothing to '
          'open', () {
        final copy = copyOn(capabilities, LocationFailure.denied);

        expect(copy.message, 'Allow location access to share where you are.');
        expect(copy.openSettings, isNull);
      });

      test('blocked access says to allow it, and opens the app settings', () {
        final copy = copyOn(capabilities, LocationFailure.deniedForever);

        expect(
          copy.message,
          'Location access is blocked. Allow it in Settings.',
        );
        expect(copy.openSettings, Geolocator.openAppSettings);
      });

      test('no fix says so, with nothing to open', () {
        final copy = copyOn(capabilities, LocationFailure.unavailable);

        expect(copy.message, 'Could not find your location.');
        expect(copy.openSettings, isNull);
      });
    });
  }
}
