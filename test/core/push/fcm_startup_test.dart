import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_startup.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/push_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/fcm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  Object? readyAnswer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    readyAnswer = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'ready' ? readyAnswer : null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
    fcmDeliveryProvider.runner.liveClient = null;
  });

  Map<String, Object?> push(String eventId) => {
    'id': 'job-$eventId',
    'data': {'event_id': eventId, 'room_id': '!r:x'},
    'appInFront': false,
  };

  test('attaching the client alone does not claim pushes yet', () async {
    await initializeFcmDelivery();
    final client = PushTestClient();

    attachFcmAppClient(client);

    expect(calls, isEmpty);
    expect(fcmDeliveryProvider.runner.liveClient, same(client));
  });

  test('once the app is ready its engine takes pushes on the client', () async {
    await initializeFcmDelivery();
    final client = PushTestClient();
    attachFcmAppClient(client);

    expect(await markFcmAppReady(), isTrue);
    await callFromNative(channel, 'push', push(r'$one'));

    expect(calls, ['ready']);
    expect(client.fetched, [r'$one']);
  });

  test('the app is never ready without a client to take pushes on', () async {
    await initializeFcmDelivery();

    expect(await markFcmAppReady(), isFalse);
    expect(calls, isEmpty);
  });

  test('reports an app engine the router passed over', () async {
    readyAnswer = false;
    await initializeFcmDelivery();
    attachFcmAppClient(PushTestClient());

    expect(await markFcmAppReady(), isFalse);
    expect(calls, ['ready']);
  });

  test('an undecodable push is answered and dropped', () async {
    await initializeFcmDelivery();
    final client = PushTestClient();
    attachFcmAppClient(client);
    await markFcmAppReady();

    await callFromNative(channel, 'push', {
      'id': 'job',
      'data': {'unrelated': 'x'},
    });

    expect(client.fetched, isEmpty);
  });

  group('where FCM is not offered', () {
    final bridge = FcmBridge(capabilities: iosCapabilities);

    test('nothing is bound and nothing is claimed', () async {
      await initializeFcmDelivery(bridge: bridge);
      final client = PushTestClient();
      attachFcmAppClient(client, bridge: bridge);

      expect(await markFcmAppReady(bridge: bridge), isFalse);
      await callFromNative(channel, 'push', push(r'$one'));

      expect(calls, isEmpty);
      expect(client.fetched, isEmpty);
      expect(fcmDeliveryProvider.runner.liveClient, isNull);
    });
  });
}
