import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  Object? failure;

  setUp(() {
    calls = [];
    failure = null;
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    messenger.setMockMethodCallHandler(nseChannel, (call) async {
      calls.add(call);
      if (failure case final Object error) throw error;
      return call.method == 'threadKey'
          ? '2d2de6b6c6565ad95bf365845db19da9'
          : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nseChannel, null));
  });

  test('sends each write with the names the native side reads', () async {
    const channel = NseChannel();

    expect(
      await channel.threadKey('!abc:zuno.im'),
      '2d2de6b6c6565ad95bf365845db19da9',
    );
    expect(await channel.writeMeta('{"v":1}'), isTrue);
    expect(await channel.writeRoom('!abc:zuno.im', '{"v":1}'), isTrue);
    await channel.deleteRoom('!abc:zuno.im');
    await channel.wipe();

    expect(calls.map((c) => [c.method, c.arguments]), [
      [
        'threadKey',
        {'room_id': '!abc:zuno.im'},
      ],
      [
        'writeMeta',
        {'json': '{"v":1}'},
      ],
      [
        'writeRoom',
        {'room_id': '!abc:zuno.im', 'json': '{"v":1}'},
      ],
      [
        'deleteRoom',
        {'room_id': '!abc:zuno.im'},
      ],
      ['wipe', null],
    ]);
  });

  group('a refusal from native code', () {
    Future<void> writeAndRead() async {
      expect(await const NseChannel().writeMeta('{}'), isFalse);
      expect(await const NseChannel().threadKey('!abc:zuno.im'), isNull);
    }

    test('reads as a failed write or nothing, and is reported', () async {
      failure = PlatformException(code: 'write_failed');

      expect(await reportsDuring(writeAndRead), [
        'nse writeMeta',
        'nse threadKey',
      ]);
    });

    test('over the keychain reads the same, but is left to the native '
        'record', () async {
      failure = PlatformException(code: 'keychain');

      expect(await reportsDuring(writeAndRead), isEmpty);
    });
  });

  test('with the flag off nothing is written', () async {
    ambientCapabilities = androidCapabilities;

    expect(await const NseChannel().writeRoom('!r:hs', '{}'), isFalse);
    await const NseChannel().wipe();

    expect(calls, isEmpty);
  });

  test('without the plugin a write reports false', () async {
    messenger.setMockMethodCallHandler(nseChannel, null);

    expect(await const NseChannel().writeMeta('{}'), isFalse);
  });
}
