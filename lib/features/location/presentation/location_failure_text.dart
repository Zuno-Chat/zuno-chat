import 'package:geolocator/geolocator.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/current_position.dart';

typedef LocationFailureCopy = ({
  String message,
  Future<bool> Function()? openSettings,
});

enum LocationGoal { seeWhereYouAre, shareWhereYouAre }

LocationFailureCopy locationFailureCopy(
  AppLocalizations l10n,
  LocationFailure reason, {
  required LocationGoal goal,
  required bool servicesSettings,
}) => switch (reason) {
  LocationFailure.servicesOff when servicesSettings => (
    message: switch (goal) {
      LocationGoal.seeWhereYouAre => l10n.locationOffTurnOnToSee,
      LocationGoal.shareWhereYouAre => l10n.locationOffTurnOnToShare,
    },
    openSettings: Geolocator.openLocationSettings,
  ),
  LocationFailure.servicesOff => (
    message: l10n.locationOffInSettings,
    openSettings: null,
  ),
  LocationFailure.denied => (
    message: switch (goal) {
      LocationGoal.seeWhereYouAre => l10n.locationAllowToSee,
      LocationGoal.shareWhereYouAre => l10n.locationAllowToShare,
    },
    openSettings: null,
  ),
  LocationFailure.deniedForever => (
    message: l10n.locationBlocked,
    openSettings: Geolocator.openAppSettings,
  ),
  LocationFailure.unavailable => (
    message: l10n.locationNotFound,
    openSettings: null,
  ),
};
