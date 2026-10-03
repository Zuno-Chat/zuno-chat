import '../../../core/push/apns_pusher.dart';
import '../../../core/push/apns_pusher_check.dart';
import '../../../core/push/push_diagnostics.dart';

typedef PushDiagnosticRow = ({String label, String value});

String pushAuthorizationLabel(PushAuthorization authorization) =>
    switch (authorization) {
      PushAuthorization.notDetermined => 'Not asked yet',
      PushAuthorization.denied => 'Not allowed',
      PushAuthorization.authorized => 'Allowed',
      PushAuthorization.provisional => 'Delivered quietly',
      PushAuthorization.ephemeral => 'Allowed for now',
      PushAuthorization.unknown => 'Unknown',
    };

String pushSettingLabel(PushSetting setting) => switch (setting) {
  PushSetting.enabled => 'On',
  PushSetting.disabled => 'Off',
  PushSetting.notSupported => 'Not available',
  PushSetting.unknown => 'Unknown',
};

String pusherCheckLabel(ApnsPusherCheck? check) => switch (check) {
  null => 'Not registered',
  ApnsPusherCheck.matches => 'Up to date',
  ApnsPusherCheck.missing =>
    'Missing. Zuno registers this device again on the next check.',
  ApnsPusherCheck.outdated =>
    'Out of date. Zuno registers this device again on the next check.',
  ApnsPusherCheck.unknown => 'Could not check. Pull down to try again.',
};

String _alertStyleLabel(PushAlertStyle style) => switch (style) {
  PushAlertStyle.none => 'None',
  PushAlertStyle.banner => 'Temporary',
  PushAlertStyle.alert => 'Persistent',
  PushAlertStyle.unknown => 'Unknown',
};

String _previewsLabel(PushPreviews previews) => switch (previews) {
  PushPreviews.always => 'Always',
  PushPreviews.whenAuthenticated => 'When unlocked',
  PushPreviews.never => 'Never',
  PushPreviews.unknown => 'Unknown',
};

String _environmentLabel(ApnsEnvironment? environment) => switch (environment) {
  null => 'Unknown',
  ApnsEnvironment.production => 'Production',
  ApnsEnvironment.development => 'Development',
};

List<PushDiagnosticRow> pushDiagnosticRows(
  PushDiagnosticsSnapshot snapshot, {
  required ApnsPusherCheck? pusherCheck,
  required int dropped,
}) {
  final settings = snapshot.settings;
  final environment = snapshot.environment;
  return [
    (
      label: 'Notifications',
      value: pushAuthorizationLabel(settings.authorization),
    ),
    (label: 'Alerts', value: pushSettingLabel(settings.alert)),
    (label: 'Banner style', value: _alertStyleLabel(settings.alertStyle)),
    (label: 'Sounds', value: pushSettingLabel(settings.sound)),
    (label: 'Badges', value: pushSettingLabel(settings.badge)),
    (label: 'Lock screen', value: pushSettingLabel(settings.lockScreen)),
    (
      label: 'Notification Center',
      value: pushSettingLabel(settings.notificationCenter),
    ),
    (label: 'Show previews', value: _previewsLabel(settings.previews)),
    (
      label: 'Time Sensitive notifications',
      value: pushSettingLabel(settings.timeSensitive),
    ),
    (
      label: 'Scheduled summary',
      value: pushSettingLabel(settings.scheduledDelivery),
    ),
    (
      label: 'Direct messages',
      value: pushSettingLabel(settings.directMessages),
    ),
    (
      label: 'Announce notifications',
      value: pushSettingLabel(settings.announcement),
    ),
    (label: 'CarPlay', value: pushSettingLabel(settings.carPlay)),
    (label: 'Critical alerts', value: pushSettingLabel(settings.criticalAlert)),
    (
      label: 'Link from iOS Settings',
      value: settings.providesAppSettings ? 'Yes' : 'No',
    ),
    (label: 'Push environment', value: _environmentLabel(environment)),
    (
      label: 'App ID for this build',
      value: environment == null
          ? 'Unknown'
          : apnsAppIdForEnvironment(environment),
    ),
    (
      label: 'Device token',
      value: snapshot.registeredForRemoteNotifications
          ? 'Received'
          : 'Not received',
    ),
    (label: 'Registration check', value: pusherCheckLabel(pusherCheck)),
    (label: 'Dropped registrations', value: '$dropped'),
  ];
}
