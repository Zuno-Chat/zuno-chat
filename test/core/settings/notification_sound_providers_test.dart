import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('all four default to on', () async {
    final container = await _containerWith({});
    addTearDown(container.dispose);

    expect(container.read(ringtoneEnabledProvider), isTrue);
    expect(container.read(callVibrationEnabledProvider), isTrue);
    expect(container.read(messageToneEnabledProvider), isTrue);
    expect(container.read(messageVibrationEnabledProvider), isTrue);
  });

  test('each reads its own stored value back', () async {
    final container = await _containerWith({
      ringtoneEnabledKey: false,
      messageVibrationEnabledKey: false,
    });
    addTearDown(container.dispose);

    expect(container.read(ringtoneEnabledProvider), isFalse);
    expect(container.read(messageVibrationEnabledProvider), isFalse);
    expect(container.read(callVibrationEnabledProvider), isTrue);
    expect(container.read(messageToneEnabledProvider), isTrue);
  });

  test('set() persists under the key the player reads', () async {
    final container = await _containerWith({});
    addTearDown(container.dispose);
    final prefs = container.read(sharedPreferencesProvider);

    await container.read(ringtoneEnabledProvider.notifier).set(false);
    await container.read(callVibrationEnabledProvider.notifier).set(false);
    await container.read(messageToneEnabledProvider.notifier).set(false);
    await container.read(messageVibrationEnabledProvider.notifier).set(false);

    expect(container.read(ringtoneEnabledProvider), isFalse);
    final asPlayerSeesThem = readNotificationSoundSettings(prefs);
    expect(asPlayerSeesThem.ringtone, isFalse);
    expect(asPlayerSeesThem.callVibration, isFalse);
    expect(asPlayerSeesThem.messageTone, isFalse);
    expect(asPlayerSeesThem.messageVibration, isFalse);
  });
}
