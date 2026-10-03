import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/apns_pusher_check.dart';
import 'package:zuno/core/push/push_diagnostics.dart';
import 'package:zuno/features/settings/presentation/push_diagnostics_display.dart';

PushDiagnosticsSnapshot _snapshot({
  PushAuthorization authorization = PushAuthorization.authorized,
  ApnsEnvironment? environment = ApnsEnvironment.production,
  bool registered = true,
}) => PushDiagnosticsSnapshot(
  settings: PushNotificationSettings(
    authorization: authorization,
    alert: PushSetting.enabled,
    sound: PushSetting.disabled,
    badge: PushSetting.enabled,
    lockScreen: PushSetting.enabled,
    notificationCenter: PushSetting.enabled,
    carPlay: PushSetting.notSupported,
    criticalAlert: PushSetting.notSupported,
    announcement: PushSetting.disabled,
    timeSensitive: PushSetting.enabled,
    scheduledDelivery: PushSetting.disabled,
    directMessages: PushSetting.unknown,
    alertStyle: PushAlertStyle.banner,
    previews: PushPreviews.whenAuthenticated,
    providesAppSettings: false,
  ),
  environment: environment,
  registeredForRemoteNotifications: registered,
);

Map<String, String> _rows(
  PushDiagnosticsSnapshot snapshot, {
  ApnsPusherCheck? check = ApnsPusherCheck.matches,
  int dropped = 0,
}) => {
  for (final row in pushDiagnosticRows(
    snapshot,
    pusherCheck: check,
    dropped: dropped,
  ))
    row.label: row.value,
};

void main() {
  test('lists every iOS notification setting, then how this device is '
      'registered', () {
    final rows = _rows(_snapshot(), dropped: 2);

    expect(rows.keys.first, 'Notifications');
    expect(rows, {
      'Notifications': 'Allowed',
      'Alerts': 'On',
      'Banner style': 'Temporary',
      'Sounds': 'Off',
      'Badges': 'On',
      'Lock screen': 'On',
      'Notification Center': 'On',
      'Show previews': 'When unlocked',
      'Time Sensitive notifications': 'On',
      'Scheduled summary': 'Off',
      'Direct messages': 'Unknown',
      'Announce notifications': 'Off',
      'CarPlay': 'Not available',
      'Critical alerts': 'Not available',
      'Link from iOS Settings': 'No',
      'Push environment': 'Production',
      'App ID for this build': 'im.zuno.chat.ios',
      'Device token': 'Received',
      'Registration check': 'Up to date',
      'Dropped registrations': '2',
    });
  });

  test('a development build names its own app id', () {
    final rows = _rows(_snapshot(environment: ApnsEnvironment.development));

    expect(rows['Push environment'], 'Development');
    expect(rows['App ID for this build'], 'im.zuno.chat.ios.dev');
  });

  test('an environment that could not be read claims no app id', () {
    final rows = _rows(_snapshot(environment: null));

    expect(rows['Push environment'], 'Unknown');
    expect(rows['App ID for this build'], 'Unknown');
  });

  test('a device Apple has not given a token says so', () {
    expect(_rows(_snapshot(registered: false))['Device token'], 'Not received');
  });

  test('each permission state reads plainly, and a quiet one is never '
      'called off', () {
    expect(
      {
        for (final state in PushAuthorization.values)
          state: pushAuthorizationLabel(state),
      },
      {
        PushAuthorization.notDetermined: 'Not asked yet',
        PushAuthorization.denied: 'Not allowed',
        PushAuthorization.authorized: 'Allowed',
        PushAuthorization.provisional: 'Delivered quietly',
        PushAuthorization.ephemeral: 'Allowed for now',
        PushAuthorization.unknown: 'Unknown',
      },
    );
  });

  test('each registration check says what happens next', () {
    expect(pusherCheckLabel(null), 'Not registered');
    expect(pusherCheckLabel(ApnsPusherCheck.matches), 'Up to date');
    expect(
      pusherCheckLabel(ApnsPusherCheck.missing),
      'Missing. Zuno registers this device again on the next check.',
    );
    expect(
      pusherCheckLabel(ApnsPusherCheck.outdated),
      'Out of date. Zuno registers this device again on the next check.',
    );
    expect(
      pusherCheckLabel(ApnsPusherCheck.unknown),
      'Could not check. Pull down to try again.',
    );
  });
}
