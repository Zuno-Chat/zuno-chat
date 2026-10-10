import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/shortcuts/home_screen_shortcut.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

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
      await callFromNative(channel, 'openRoom', '!live:example.org');
      expect(await future, '!live:example.org');
    },
  );

  group('on iOS, a tapped Apple push opens its room', () {
    final ios = capabilitiesFor(AppPlatform.ios);
    late List<String> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'pinShortcut' ? true : '!pushed:example.org';
      });
    });

    test('the launch room is the one whose notification started the '
        'app', () async {
      expect(
        await takeLaunchRoomShortcut(capabilities: ios),
        '!pushed:example.org',
      );
      expect(calls, ['takeLaunchRoomId']);
    });

    test('a tap while running opens its room', () async {
      channel.setMethodCallHandler(null);
      initHomeScreenShortcutChannel(capabilities: ios);
      final opened = onOpenRoomShortcut.first;

      await callFromNative(channel, 'openRoom', '!pushed:example.org');

      expect(await opened, '!pushed:example.org');
    });

    test('pinning still reports not added and never calls native', () async {
      final pinned = await pinRoomShortcut(
        roomId: '!abc:example.org',
        label: 'Alice',
        capabilities: ios,
      );

      expect(pinned, isFalse);
      expect(calls, isEmpty);
    });
  });

  group('on a platform whose native side opens no rooms', () {
    final neither = capabilitiesLike(iosCapabilities, nativeRoomOpens: false);
    late List<String> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'pinShortcut' ? true : '!room:example.org';
      });
    });

    test('there is never a launch room', () async {
      expect(await takeLaunchRoomShortcut(capabilities: neither), isNull);
      expect(calls, isEmpty);
    });

    test('pinning reports not added and never calls native', () async {
      final pinned = await pinRoomShortcut(
        roomId: '!abc:example.org',
        label: 'Alice',
        capabilities: neither,
      );

      expect(pinned, isFalse);
      expect(calls, isEmpty);
    });

    test('no handler is registered for opened rooms', () async {
      channel.setMethodCallHandler(null);
      initHomeScreenShortcutChannel(capabilities: neither);

      var replied = false;
      ByteData? reply;
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('openRoom', '!live:example.org'),
        ),
        (data) {
          replied = true;
          reply = data;
        },
      );

      expect(replied, isTrue);
      expect(reply, isNull);
    });
  });
}
