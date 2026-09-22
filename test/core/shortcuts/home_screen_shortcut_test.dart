import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/shortcuts/home_screen_shortcut.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/shortcuts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    initHomeScreenShortcutChannel();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('takeLaunchRoomShortcut returns the native side\'s room ID', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takeLaunchRoomId');
      return '!room:example.org';
    });
    expect(await takeLaunchRoomShortcut(), '!room:example.org');
  });

  test(
    'takeLaunchRoomShortcut returns null when there was no shortcut launch',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await takeLaunchRoomShortcut(), isNull);
    },
  );

  test(
    'pinRoomShortcut sends the expected arguments and reports the result',
    () async {
      Map<Object?, Object?>? sentArgs;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pinShortcut');
        sentArgs = call.arguments as Map<Object?, Object?>;
        return true;
      });
      final result = await pinRoomShortcut(
        roomId: '!abc:example.org',
        label: 'Alice',
      );
      expect(result, isTrue);
      expect(sentArgs?['id'], 'room_!abc:example.org');
      expect(sentArgs?['roomId'], '!abc:example.org');
      expect(sentArgs?['label'], 'Alice');
    },
  );

  test(
    'pinRoomShortcut reports false when the native side returns null',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(
        await pinRoomShortcut(roomId: '!abc:example.org', label: 'Alice'),
        isFalse,
      );
    },
  );

  test(
    'onOpenRoomShortcut streams a room ID delivered while already running',
    () async {
      final future = onOpenRoomShortcut.first;
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('openRoom', '!live:example.org'),
        ),
        (data) {},
      );
      expect(await future, '!live:example.org');
    },
  );
}
