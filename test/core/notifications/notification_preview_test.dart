import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/notification_preview.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  test('Name and message is the default and a bad value reads as it', () async {
    SharedPreferences.setMockInitialValues({notificationPreviewKey: 'bogus'});
    final prefs = await SharedPreferences.getInstance();

    expect(notificationPreviewFromPreferences(prefs), NotificationPreview.full);
  });

  test('the chosen level is stored and read back', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await container
        .read(notificationPreviewProvider.notifier)
        .set(NotificationPreview.nothing);

    expect(
      container.read(notificationPreviewProvider),
      NotificationPreview.nothing,
    );
    expect(prefs.getString(notificationPreviewKey), 'nothing');
  });

  test('without the extension every platform reads Name and message', () async {
    SharedPreferences.setMockInitialValues({notificationPreviewKey: 'nothing'});

    expect(
      await currentNotificationPreview(capabilities: androidCapabilities),
      NotificationPreview.full,
    );
    expect(
      await currentNotificationPreview(
        capabilities: capabilitiesLike(iosCapabilities, nseNotifications: true),
      ),
      NotificationPreview.nothing,
    );
  });

  test('only systems without the retention fix are flagged', () {
    for (final version in [
      'Version 15.8.7 (Build 19H1)',
      '16.7.15',
      '17.7.11',
      '18.7.7',
      '26.4.1',
      '26.4',
    ]) {
      expect(notificationRetentionUnpatched(version), isTrue, reason: version);
    }
    for (final version in [
      '15.8.8',
      '16.7.16',
      '18.7.8',
      '26.4.2',
      '26.5',
      '27.0',
      'unknown',
    ]) {
      expect(notificationRetentionUnpatched(version), isFalse, reason: version);
    }
  });
}
