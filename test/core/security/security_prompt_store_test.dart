import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecurityPromptStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = SecurityPromptStore(await SharedPreferences.getInstance());
  });

  test('nothing has been asked yet on a fresh install', () {
    expect(store.lastPrompted(), isNull);
    expect(store.promptInFlight, isFalse);
  });

  test('markPrompted is visible before its write completes', () {
    final pending = store.markPrompted();

    expect(store.lastPrompted(), isNotNull);
    return pending;
  });

  test('markPrompted survives a restart, via the stored value', () async {
    await store.markPrompted();

    final reloaded = SecurityPromptStore(await SharedPreferences.getInstance());

    expect(reloaded.lastPrompted(), isNotNull);
  });

  test('a stored prompt from a previous session is read back', () async {
    final earlier = DateTime(2026, 9, 1);
    SharedPreferences.setMockInitialValues({
      'security.recovery_prompt_ms': earlier.millisecondsSinceEpoch,
    });

    final restored = SecurityPromptStore(await SharedPreferences.getInstance());

    expect(restored.lastPrompted(), earlier);
  });

  test('a sign-in after a sign-out that wiped the app data starts with no '
      'prompt on record, even without a restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final logins = StreamController<bool>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isLoggedInProvider.overrideWith((ref) => logins.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(securityPromptStoreProvider, (_, _) {});
    logins.add(true);
    await pumpEventQueue();
    await container.read(securityPromptStoreProvider).markPrompted();

    await prefs.clear();
    logins.add(false);
    await pumpEventQueue();
    logins.add(true);
    await pumpEventQueue();

    expect(container.read(securityPromptStoreProvider).lastPrompted(), isNull);
  });
}
