import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';

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
}
