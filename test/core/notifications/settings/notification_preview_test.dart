import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

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

  test('every platform reads the stored level', () async {
    SharedPreferences.setMockInitialValues({notificationPreviewKey: 'nothing'});

    expect(await currentNotificationPreview(), NotificationPreview.nothing);
  });

  test('the stored level is read again, so a level chosen after this engine '
      'cached its preferences applies', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    await SharedPreferencesStorePlatform.instance.setValue(
      'String',
      'flutter.$notificationPreviewKey',
      NotificationPreview.nothing.name,
    );

    expect(await currentNotificationPreview(), NotificationPreview.nothing);
  });

  test('a level nobody chose reads as Name and message', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await currentNotificationPreview(), NotificationPreview.full);
  });

  test('only Nothing hides who is calling', () {
    final l10n = englishLocalizations;
    expect(NotificationPreview.full.callName('Alice', l10n), 'Alice');
    expect(NotificationPreview.nameOnly.callName('Alice', l10n), 'Alice');
    expect(NotificationPreview.nothing.callName('Alice', l10n), 'Zuno call');
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
