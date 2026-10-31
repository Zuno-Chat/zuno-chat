import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';

import '../../../helpers/fake_call_style_channel.dart';

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

  test('reads the ringing call native code remembered', () async {
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
    final postedAt = DateTime(2030, 1, 1, 12);
    await withClock(Clock.fixed(postedAt), () => saveRingingCall(prefs, call));

    final read = withClock(
      Clock.fixed(postedAt.add(const Duration(seconds: 46))),
      () => readRingingCall(prefs),
    );

    expect(read, isNull);
  });

  test('a corrupt record is ignored instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'calls.ringing_notification': 'not json',
    });

    expect(readRingingCall(await SharedPreferences.getInstance()), isNull);
  });

  group('the active ring native code reports', () {
    test('names its room, call, caller and kind', () {
      expect(
        ringingCallFrom({
          'roomId': '!room:example.org',
          'callId': 'c1',
          'callerId': '@alice:example.org',
          'isVideo': true,
        }),
        call,
      );
    });

    test('without a caller or kind, names no caller and rings as voice', () {
      expect(ringingCallFrom({'roomId': '!room:example.org', 'callId': 'c1'}), (
        roomId: '!room:example.org',
        callId: 'c1',
        callerId: '',
        isVideo: false,
      ));
    });

    test('is none without its room or call', () {
      expect(ringingCallFrom(null), isNull);
      expect(ringingCallFrom({'callId': 'c1'}), isNull);
      expect(ringingCallFrom({'roomId': '!room:example.org'}), isNull);
    });
  });
}
