import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const call = (
    roomId: '!room:example.org',
    callId: 'c1',
    callerId: '@alice:example.org',
    isVideo: true,
  );

  Future<SharedPreferences> emptyPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('round-trips the ringing call', () async {
    final prefs = await emptyPrefs();

    await saveRingingCall(prefs, call);

    final stored = readRingingCall(prefs);
    expect(stored?.roomId, '!room:example.org');
    expect(stored?.callId, 'c1');
    expect(stored?.callerId, '@alice:example.org');
    expect(stored?.isVideo, isTrue);
  });

  test('nothing stored means nothing is ringing', () async {
    expect(readRingingCall(await emptyPrefs()), isNull);
  });

  test('a stale record is ignored rather than rung for', () async {
    final prefs = await emptyPrefs();
    await saveRingingCall(prefs, call);

    final later = DateTime.now().add(const Duration(seconds: 46));

    expect(readRingingCall(prefs, now: later), isNull);
  });

  test('a corrupt record is ignored instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'calls.ringing_notification': 'not json',
    });

    expect(readRingingCall(await SharedPreferences.getInstance()), isNull);
  });

  test('clear() forgets it', () async {
    final prefs = await emptyPrefs();
    await saveRingingCall(prefs, call);

    await clearRingingCall(prefs);

    expect(readRingingCall(prefs), isNull);
  });
}
