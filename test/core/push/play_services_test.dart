import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/play_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/play_services');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];
  Object? answer;

  setUp(() {
    calls.clear();
    answer = 'AVAILABLE';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (answer is Exception) throw answer!;
      return answer;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('parses each availability the native side reports', () async {
    for (final entry in {
      'AVAILABLE': PlayServicesAvailability.available,
      'UPDATE_REQUIRED': PlayServicesAvailability.updateRequired,
      'UNAVAILABLE': PlayServicesAvailability.unavailable,
    }.entries) {
      answer = entry.key;
      expect(await PlayServicesProbe.instance.check(), entry.value);
    }
    expect(calls, everyElement('checkPlayServices'));
  });

  test('an unrecognised answer is unavailable, never available', () async {
    answer = 'SOMETHING_ELSE';
    expect(
      await PlayServicesProbe.instance.check(),
      PlayServicesAvailability.unavailable,
    );
  });

  test('a failing channel is unavailable, not a crash', () async {
    answer = PlatformException(code: 'error');
    expect(
      await PlayServicesProbe.instance.check(),
      PlayServicesAvailability.unavailable,
    );
  });

  test('requestFix calls through and swallows a refusal', () async {
    answer = PlatformException(code: 'error');
    await PlayServicesProbe.instance.requestFix();
    expect(calls, ['fixPlayServices']);
  });
}
