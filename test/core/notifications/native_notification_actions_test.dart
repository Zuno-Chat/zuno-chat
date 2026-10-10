import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/native_notification_actions.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/notification_actions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final enabled = capabilitiesLike(
    iosCapabilities,
    nativeNotificationActions: true,
  );
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (_) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test(
    'without native actions nothing is taken, finished or listened to',
    () async {
      for (final capabilities in [
        androidCapabilities,
        capabilitiesLike(iosCapabilities, nativeNotificationActions: false),
      ]) {
        final actions = NativeNotificationActionsChannel(
          capabilities: capabilities,
        );
        final batch = await actions.take();
        await actions.finish('a1', ok: true);
        actions.listen(() => fail('no hint expected'));
        expect(actions.enabled, isFalse);
        expect(batch.actions, isEmpty);
        expect(batch.unreadable, isEmpty);
      }
      expect(calls, isEmpty);
    },
  );

  test('a Reply from an extension notification arrives with its room token, '
      'time and text', () async {
    answer = (_) => [
      {
        'id': 'a1',
        'kind': 'reply',
        'roomToken': '2d2de6b6c6565ad95bf365845db19da9',
        'eventSeconds': 1790000000,
        'replyText': 'on my way',
      },
    ];

    final batch = await NativeNotificationActionsChannel(capabilities: enabled)
        .take();

    expect(calls.single.method, 'takeActions');
    expect(batch.actions, [
      const NativeNotificationAction(
        id: 'a1',
        kind: NativeNotificationActionKind.reply,
        roomToken: '2d2de6b6c6565ad95bf365845db19da9',
        eventSeconds: 1790000000,
        replyText: 'on my way',
      ),
    ]);
  });

  test(
    'Mark as read on a post Zuno made arrives with its room and event',
    () async {
      answer = (_) => [
        {
          'id': 'm1',
          'kind': 'markRead',
          'roomId': '!r:example.org',
          'eventId': r'$e',
        },
      ];

      final batch = await NativeNotificationActionsChannel(
        capabilities: enabled,
      ).take();

      expect(
        batch.actions.single,
        const NativeNotificationAction(
          id: 'm1',
          kind: NativeNotificationActionKind.markRead,
          roomId: '!r:example.org',
          eventId: r'$e',
        ),
      );
    },
  );

  test('an entry Zuno cannot read is reported by its id, so native code can '
      'finish it', () async {
    answer = (_) => [
      {'id': 'bad-kind', 'kind': 'forward', 'roomId': '!r:example.org'},
      {'id': 'no-room', 'kind': 'reply', 'replyText': 'hi'},
      {'kind': 'reply', 'roomId': '!r:example.org'},
      'not a map',
    ];

    final batch = await NativeNotificationActionsChannel(capabilities: enabled)
        .take();

    expect(batch.actions, isEmpty);
    expect(batch.unreadable, ['bad-kind', 'no-room']);
  });

  test('a missing native side or a native error takes nothing and finishes '
      'quietly', () async {
    final actions = NativeNotificationActionsChannel(capabilities: enabled);
    messenger.setMockMethodCallHandler(channel, null);
    expect((await actions.take()).actions, isEmpty);
    await actions.finish('a1', ok: true);

    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'boom'),
    );
    expect((await actions.take()).actions, isEmpty);
    await actions.finish('a1', ok: true);
  });

  test('finishing tells native code the id and whether it worked', () async {
    await NativeNotificationActionsChannel(capabilities: enabled)
        .finish('a1', ok: false);

    expect(calls.single.method, 'finish');
    expect(calls.single.arguments, {'id': 'a1', 'ok': false});
  });

  test(
    'the native hint that actions are waiting reaches the listener',
    () async {
      var hints = 0;
      NativeNotificationActionsChannel(capabilities: enabled)
          .listen(() => hints++);

      await callFromNative(channel, 'actionsAvailable');

      expect(hints, 1);
    },
  );
}
