import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/fcm_registration_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('round-trips a confirmed token', () async {
    final prefs = await prefsWith({});
    await saveFcmRegistration(prefs, token: 'token-abc');
    expect(readFcmRegistration(prefs), 'token-abc');
  });

  test('nothing stored reads as no registration', () async {
    expect(readFcmRegistration(await prefsWith({})), isNull);
  });

  test('an empty stored token reads as no registration', () async {
    final prefs = await prefsWith({'push.fcm.token': ''});
    expect(readFcmRegistration(prefs), isNull);
  });

  test('clearing forgets it', () async {
    final prefs = await prefsWith({'push.fcm.token': 'token-abc'});
    await clearFcmRegistration(prefs);
    expect(readFcmRegistration(prefs), isNull);
  });
}
