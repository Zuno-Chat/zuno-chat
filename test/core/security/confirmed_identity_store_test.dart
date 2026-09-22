import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/security/confirmed_identity_store.dart';

Future<ConfirmedIdentityStore> _store([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return ConfirmedIdentityStore(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remembers the identity a person was confirmed with', () async {
    final store = await _store();
    await store.remember('@bob:example.org', 'KEY_A');
    expect(store.confirmedIdentityKey('@bob:example.org'), 'KEY_A');
  });

  test('records when, so Room info can say more than whether', () async {
    final store = await _store();
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    await store.remember('@bob:example.org', 'KEY_A');
    final at = store.confirmedAt('@bob:example.org');
    expect(at, isNotNull);
    expect(at!.isAfter(before), isTrue);
  });

  test('knows nothing about someone never confirmed', () async {
    final store = await _store();
    expect(store.confirmedIdentityKey('@bob:example.org'), isNull);
    expect(store.confirmedAt('@bob:example.org'), isNull);
  });

  test('an entry stored before timestamps existed has no date', () async {
    final store = await _store({
      'security.confirmed_identity.@bob:example.org': 'KEY_A',
    });
    expect(store.confirmedIdentityKey('@bob:example.org'), 'KEY_A');
    expect(store.confirmedAt('@bob:example.org'), isNull);
  });

  test('re-confirming replaces the key and the date', () async {
    final store = await _store();
    await store.remember('@bob:example.org', 'KEY_OLD');
    await store.remember('@bob:example.org', 'KEY_NEW');
    expect(store.confirmedIdentityKey('@bob:example.org'), 'KEY_NEW');
  });

  test('forget clears the date too, not just the key', () async {
    final store = await _store();
    await store.remember('@bob:example.org', 'KEY_A');
    await store.forget('@bob:example.org');
    expect(store.confirmedIdentityKey('@bob:example.org'), isNull);
    expect(store.confirmedAt('@bob:example.org'), isNull);
  });

  test('forgetAll clears every person and leaves other prefs alone', () async {
    final store = await _store({'settings.theme_mode': 'dark'});
    await store.remember('@bob:example.org', 'KEY_A');
    await store.remember('@carol:example.org', 'KEY_B');
    await store.forgetAll();
    expect(store.confirmedIdentityKey('@bob:example.org'), isNull);
    expect(store.confirmedIdentityKey('@carol:example.org'), isNull);
    expect(store.confirmedAt('@carol:example.org'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.theme_mode'), 'dark');
  });
}
