import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/message_notification_image.dart';
import 'package:zuno/core/notifications/notification_image_publisher.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/conversations');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final image = NotificationImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/png',
  );

  late List<MethodCall> calls;

  setUp(() => calls = []);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  test('hands the image to the native side and returns its uri', () async {
    answer((_) => 'content://zuno/thumb');

    expect(await publishNotificationImage(image), 'content://zuno/thumb');
    expect(calls.single.method, 'publishNotificationImage');
    expect(calls.single.arguments, {
      'bytes': image.bytes,
      'mimeType': 'image/png',
    });
  });

  test('a native refusal publishes nothing', () async {
    answer((_) => throw PlatformException(code: 'bad_args'));

    expect(await publishNotificationImage(image), isNull);
  });

  test('no native side at all publishes nothing', () async {
    expect(await publishNotificationImage(image), isNull);
  });

  test('a platform without notification images never calls native', () async {
    answer((_) => 'content://zuno/thumb');

    final uri = await publishNotificationImage(
      image,
      capabilities: capabilitiesFor(AppPlatform.ios),
    );

    expect(uri, isNull);
    expect(calls, isEmpty);
  });
}
