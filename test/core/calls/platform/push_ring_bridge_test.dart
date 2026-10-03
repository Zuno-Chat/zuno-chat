import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/platform/native_ring.dart';
import 'package:zuno/core/calls/platform/push_ring_bridge.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('a native ring', () {
    test('reads a pushed ring with its room, call and source', () {
      final ring = NativeRing.tryParse({
        'uuid': 'U1',
        'roomId': '!r:zuno.im',
        'callId': 'c1',
        'callerId': '@alice:zuno.im',
        'isVideo': true,
        'video': true,
        'source': 'push',
      });

      expect(ring?.uuid, 'U1');
      expect(ring?.roomId, '!r:zuno.im');
      expect(ring?.callId, 'c1');
      expect(ring?.callerId, '@alice:zuno.im');
      expect(ring?.video, isTrue);
      expect(ring?.source, NativeRingSource.push);
      expect(ring?.bound, isTrue);
    });

    test('a ring without its call is not bound', () {
      final ring = NativeRing.tryParse({'uuid': 'U2', 'source': 'generic'});

      expect(ring?.bound, isFalse);
      expect(ring?.callerId, '');
    });

    test('a ring without a uuid or a known source is no ring', () {
      expect(NativeRing.tryParse({'source': 'push'}), isNull);
      expect(NativeRing.tryParse({'uuid': 'U3', 'source': 'pager'}), isNull);
      expect(NativeRing.tryParse('ringing'), isNull);
    });
  });

  group('the bridge to CallKit', () {
    late RecordedCallsChannel native;

    setUp(() {
      native = installFakeCallsChannel(
        reply: (call) => call.method == 'bindIncoming' ? true : null,
      );
    });

    test('sends updates, bindings, unbound ends and sent declines', () async {
      final bridge = pushRingBridgeFor(
        capabilitiesLike(iosCapabilities, voipRing: true),
      );

      await bridge.updateIncoming(
        roomId: '!r:zuno.im',
        callId: 'c1',
        name: 'Alice',
        video: true,
      );
      final bound = await bridge.bindIncoming(
        uuid: 'U1',
        roomId: '!r:zuno.im',
        callId: 'c1',
        callerId: '@alice:zuno.im',
        name: 'Alice',
        video: false,
      );
      await bridge.endUnbound('U2');
      await bridge.declineSent(roomId: '!r:zuno.im', callId: 'c1');

      expect(bound, isTrue);
      expect(native.calls.map((c) => [c.method, c.arguments]), [
        [
          'updateIncoming',
          {
            'roomId': '!r:zuno.im',
            'callId': 'c1',
            'name': 'Alice',
            'video': true,
          },
        ],
        [
          'bindIncoming',
          {
            'uuid': 'U1',
            'roomId': '!r:zuno.im',
            'callId': 'c1',
            'callerId': '@alice:zuno.im',
            'name': 'Alice',
            'video': false,
          },
        ],
        [
          'endUnbound',
          {'uuid': 'U2'},
        ],
        [
          'declineSent',
          {'roomId': '!r:zuno.im', 'callId': 'c1'},
        ],
      ]);
    });

    test('without VoIP rings nothing reaches native code', () async {
      final bridge = pushRingBridgeFor(androidCapabilities);

      expect(
        await bridge.bindIncoming(
          uuid: 'U1',
          roomId: '!r:zuno.im',
          callId: 'c1',
          callerId: '',
          name: '',
          video: false,
        ),
        isFalse,
      );
      await bridge.declineSent(roomId: '!r:zuno.im', callId: 'c1');

      expect(native.calls, isEmpty);
    });

    test('a binding native code cannot answer is not bound', () async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('zuno/calls'),
        null,
      );

      expect(
        await const CallKitPushRingBridge().bindIncoming(
          uuid: 'U1',
          roomId: '!r:zuno.im',
          callId: 'c1',
          callerId: '',
          name: '',
          video: false,
        ),
        isFalse,
      );
    });
  });

  group('rings native code announces', () {
    setUp(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => call.method == 'initialize' ? true : null,
      );
      installFakeCallsChannel();
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    Future<List<NativeRing>> ringsPassedOn() async {
      final rings = <NativeRing>[];
      final sub = CallNotificationService.instance.onNativeRing.listen(
        rings.add,
      );
      addTearDown(sub.cancel);

      await sendFromNative('ringing', {'uuid': 'U9', 'source': 'generic'});
      await pumpEventQueue();
      return rings;
    }

    test('with VoIP rings, a ring is passed on whole', () async {
      ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);

      final rings = await ringsPassedOn();

      expect(rings.single.uuid, 'U9');
      expect(rings.single.source, NativeRingSource.generic);
    });

    test('without VoIP rings, nothing is passed on', () async {
      ambientCapabilities = androidCapabilities;

      expect(await ringsPassedOn(), isEmpty);
    });
  });
}
