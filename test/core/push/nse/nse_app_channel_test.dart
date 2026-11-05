import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/push/nse/nse_app_channel.dart';
import 'package:zuno/core/push/nse/opaque_thread_ids.dart';

import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/nse');
  final ios = capabilitiesLike(iosCapabilities, nseNotifications: true);
  late List<MethodCall> calls;
  Object? reply;

  setUp(() {
    calls = [];
    reply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

  test('shown events and credentials reach the native store', () async {
    final nse = NseAppChannel(capabilities: ios);
    reply = true;

    await nse.writeShown([
      const ExtensionClaim.event(r'$e1'),
      const ExtensionClaim.invite('!r:x'),
    ]);
    final stored = await nse.setCredential('cred', expiresTs: 9);

    expect(stored, isTrue);
    expect(calls.map((c) => [c.method, c.arguments]), [
      [
        'writeShown',
        {
          'claims': [
            {'kind': 'event', 'id': r'$e1'},
            {'kind': 'invite', 'id': '!r:x'},
          ],
        },
      ],
      [
        'setCredential',
        {'credential': 'cred', 'expires_ts': 9},
      ],
    ]);
  });

  test('asks the native store in one call which claims the extension still '
      'holds; without it, or on an error, it holds none', () async {
    const event = ExtensionClaim.event(r'$e1');
    const invite = ExtensionClaim.invite('!r:x');
    const other = ExtensionClaim.event(r'$e2');
    reply = [true, false, true];
    expect(
      await NseAppChannel(capabilities: ios)
          .shownByExtension([event, invite, other]),
      {event, other},
    );
    expect(calls.single.method, 'shownByExtension');
    expect(calls.single.arguments, {
      'claims': [
        {'kind': 'event', 'id': r'$e1'},
        {'kind': 'invite', 'id': '!r:x'},
        {'kind': 'event', 'id': r'$e2'},
      ],
    });

    reply = [true];
    expect(
      await NseAppChannel(capabilities: ios).shownByExtension([event, invite]),
      {event},
    );

    expect(
      await NseAppChannel(capabilities: androidCapabilities)
          .shownByExtension([event]),
      isEmpty,
    );
    expect(calls, hasLength(2));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'boom'),
        );
    expect(
      await NseAppChannel(capabilities: ios).shownByExtension([event]),
      isEmpty,
    );
  });

  test('hears each alert native code hid in front until told to '
      'stop', () async {
    final nse = NseAppChannel(capabilities: ios);
    var hidden = 0;
    nse.onAlertHidden(() => hidden++);
    addTearDown(() => nse.onAlertHidden(null));

    await callFromNative(channel, 'alertHiddenInFront');
    await callFromNative(channel, 'something else');
    expect(hidden, 1);

    nse.onAlertHidden(null);
    await callFromNative(channel, 'alertHiddenInFront');
    expect(hidden, 1);
  });

  test('marks and outcomes are read from records', () async {
    final nse = NseAppChannel(capabilities: ios);
    reply = [
      {'kind': 'invite', 'room': '!r:x', 'ts': 5},
      {'kind': 'broken'},
    ];
    final marks = await nse.takeMarks();
    reply = [
      {'kind': 'counter', 'key': 'nse.c.20260921.o.utd', 'count': 2},
      {'kind': 'generation', 'value': 'g1'},
    ];
    final report = await nse.readOutcomes();

    expect(marks.single.room, '!r:x');
    expect(report.counters, {'nse.c.20260921.o.utd': 2});
    expect(report.generation, 'g1');
  });

  test(
    'without the extension, or without the native side, nothing is sent',
    () async {
      final android = NseAppChannel(capabilities: androidCapabilities);
      await android.writeShown([const ExtensionClaim.event(r'$e')]);
      expect(await android.syncBadge(['t']), isNull);
      expect(calls, isEmpty);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await NseAppChannel(capabilities: ios).syncBadge(['t']), isNull);
      expect(await NseAppChannel(capabilities: ios).takeMarks(), isEmpty);
    },
  );

  test('a native error reads as nothing done', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'boom'),
        );

    expect(await NseAppChannel(capabilities: ios).setCredential(null), isFalse);
  });

  group('opaque thread ids', () {
    test('are asked for once per room and map back to their room', () async {
      final asked = <String>[];
      final ids = OpaqueThreadIds(
        threadKey: (roomId) async {
          asked.add(roomId);
          return 'tok-$roomId';
        },
      );

      expect(await ids.tokenFor('!a'), 'tok-!a');
      expect(await ids.tokenFor('!a'), 'tok-!a');
      expect(await ids.tokensFor(['!a', '!b']), ['tok-!a', 'tok-!b']);
      expect(await ids.roomFor('tok-!c', ['!a', '!b', '!c']), '!c');
      expect(asked, ['!a', '!b', '!c']);
    });

    test('a room list that changes while tokens are asked for still maps '
        'back', () async {
      final rooms = ['!a', '!b'];
      final ids = OpaqueThreadIds(
        threadKey: (roomId) async {
          if (roomId == '!a') rooms.add('!late');
          return 'tok-$roomId';
        },
      );

      expect(await ids.roomFor('tok-!b', rooms.map((id) => id)), '!b');
    });

    test('an unknown token or an unanswered room maps to nothing', () async {
      final ids = OpaqueThreadIds(threadKey: (_) async => null);

      expect(await ids.tokenFor('!a'), isNull);
      expect(await ids.tokensFor(['!a']), isEmpty);
      expect(await ids.roomFor('tok', ['!a']), isNull);
    });
  });

  group('opening a room from a notification', () {
    final ids = OpaqueThreadIds(threadKey: (roomId) async => 'tok-$roomId');

    test('a token from the extension opens its room', () async {
      expect(
        await roomIdToOpen(
          't:tok-!b',
          ['!a', '!b'],
          opaque: true,
          threadIds: ids,
        ),
        '!b',
      );
    });

    test(
      'a room id passes through, and a token for no room opens nothing',
      () async {
        expect(
          await roomIdToOpen('!a', ['!a'], opaque: true, threadIds: ids),
          '!a',
        );
        expect(
          await roomIdToOpen('t:tok-!z', ['!a'], opaque: true, threadIds: ids),
          isNull,
        );
        expect(
          await roomIdToOpen('t:x', ['!a'], opaque: false, threadIds: ids),
          't:x',
        );
      },
    );
  });
}
