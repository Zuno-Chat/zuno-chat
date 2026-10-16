import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';

void main() {
  Future<void> initializeService() async {
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    SharedPreferences.setMockInitialValues({});
    await CallNotificationService.instance.initialize(claimLiveRoutes: false);
  }

  group('callNotificationResponseFrom', () {
    const payload =
        '{"roomId":"!room:example.org","callId":"c1",'
        '"callerId":"@alice:example.org","isVideo":true}';

    test('parses an accept action with its call', () {
      final response = callNotificationResponseFrom(
        actionId: 'accept',
        payload: payload,
      );
      expect(response?.action, CallNotificationAction.accept);
      expect(response?.call.roomId, '!room:example.org');
      expect(response?.call.callId, 'c1');
      expect(response?.call.callerId, '@alice:example.org');
      expect(response?.call.isVideo, isTrue);
    });

    test('parses a decline action too', () {
      expect(
        callNotificationResponseFrom(
          actionId: 'decline',
          payload: payload,
        )?.action,
        CallNotificationAction.decline,
      );
    });

    test('ignores a body tap and a message notification', () {
      expect(
        callNotificationResponseFrom(actionId: null, payload: payload),
        isNull,
      );
      expect(
        callNotificationResponseFrom(
          actionId: 'accept',
          payload: '{"type":"message","roomId":"!room:example.org"}',
        ),
        isNull,
      );
    });

    test('ignores malformed or missing payloads instead of throwing', () {
      expect(
        callNotificationResponseFrom(actionId: 'accept', payload: null),
        isNull,
      );
      expect(
        callNotificationResponseFrom(actionId: 'accept', payload: 'not json'),
        isNull,
      );
      expect(
        callNotificationResponseFrom(actionId: 'accept', payload: '[1,2,3]'),
        isNull,
      );
    });

    test('treats a missing isVideo as a voice call', () {
      final response = callNotificationResponseFrom(
        actionId: 'accept',
        payload: '{"roomId":"!r:example.org","callId":"c1"}',
      );
      expect(response?.call.isVideo, isFalse);
    });
  });

  group('ongoing-call hang up', () {
    setUp(initializeService);

    test('ignores any other method on the calls channel', () async {
      var fired = false;
      final sub = CallNotificationService.instance.onHangUp.listen((_) {
        fired = true;
      });
      addTearDown(sub.cancel);

      await sendFromNative('somethingElse');
      await pumpEventQueue();

      expect(fired, isFalse);
    });
  });

  group('picture in picture', () {
    setUp(initializeService);

    test('tracks entering and leaving the system window', () async {
      final service = CallNotificationService.instance;
      expect(service.inPictureInPicture.value, isFalse);

      await sendFromNative('pictureInPictureChanged', true);
      expect(service.inPictureInPicture.value, isTrue);

      await sendFromNative('pictureInPictureChanged', false);
      expect(service.inPictureInPicture.value, isFalse);
    });

    test('tracks whether the system window can use the camera', () async {
      final service = CallNotificationService.instance;
      addTearDown(() => service.pictureInPictureCamera.value = false);
      expect(service.pictureInPictureCamera.value, isFalse);

      await sendFromNative('pictureInPictureCameraChanged', true);
      expect(service.pictureInPictureCamera.value, isTrue);
      expect(service.inPictureInPicture.value, isFalse);

      await sendFromNative('pictureInPictureCameraChanged', false);
      expect(service.pictureInPictureCamera.value, isFalse);
    });
  });

  group('proximity screen off', () {
    setUp(initializeService);

    test('sends the enabled flag to the platform', () async {
      final toNative = installFakeCallsChannel();

      await CallNotificationService.instance.setProximityScreenOff(true);
      await CallNotificationService.instance.setProximityScreenOff(false);

      expect(toNative.calls.map((c) => [c.method, c.arguments]), [
        [
          'setProximityScreenOff',
          {'enabled': true},
        ],
        [
          'setProximityScreenOff',
          {'enabled': false},
        ],
      ]);
    });

    test('is a no-op when the platform side is missing', () async {
      await expectLater(
        CallNotificationService.instance.setProximityScreenOff(true),
        completes,
      );
    });
  });
}
