import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/apns_alert_removal.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/apns');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 2;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks once for each read room, in a stable order, and reports how '
      'many alerts went', () async {
    final removal = ApnsAlertRemoval(capabilities: iosCapabilities);

    final removed = await removal.removeForReadRooms([
      '!b:example.org',
      '!a:example.org',
      '!b:example.org',
    ]);

    expect(removed, 2);
    expect(calls.single.method, 'removeDelivered');
    expect(calls.single.arguments, {
      'roomIds': ['!a:example.org', '!b:example.org'],
    });
  });

  test('asks nothing where Apple push is not used', () async {
    final removal = ApnsAlertRemoval(capabilities: androidCapabilities);

    expect(await removal.removeForReadRooms(['!a:example.org']), 0);
    expect(calls, isEmpty);
  });

  test('asks nothing when no room was read', () async {
    final removal = ApnsAlertRemoval(capabilities: iosCapabilities);

    expect(await removal.removeForReadRooms(const []), 0);
    expect(calls, isEmpty);
  });

  test('without the native handler nothing is removed and nothing '
      'throws', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final removal = ApnsAlertRemoval(capabilities: iosCapabilities);

    expect(await removal.removeForReadRooms(['!a:example.org']), 0);
  });

  test('a native failure removes nothing and does not throw', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'unavailable'),
    );
    final removal = ApnsAlertRemoval(capabilities: iosCapabilities);

    expect(await removal.removeForReadRooms(['!a:example.org']), 0);
  });
}
