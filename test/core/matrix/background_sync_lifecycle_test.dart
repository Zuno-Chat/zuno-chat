import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/background_sync_lifecycle.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';

void main() {
  group('shouldPauseBackgroundSync', () {
    test('pauses on background when delivery is FCM', () {
      expect(
        shouldPauseBackgroundSync(
          AppLifecycleState.paused,
          NotificationDeliveryMode.fcm,
          inCall: false,
        ),
        isTrue,
      );
    });

    test('pauses on background when delivery is UnifiedPush', () {
      expect(
        shouldPauseBackgroundSync(
          AppLifecycleState.paused,
          NotificationDeliveryMode.unifiedPush,
          inCall: false,
        ),
        isTrue,
      );
    });

    test('never pauses when delivery is the background service', () {
      expect(
        shouldPauseBackgroundSync(
          AppLifecycleState.paused,
          NotificationDeliveryMode.backgroundService,
          inCall: false,
        ),
        isFalse,
      );
    });

    test('never pauses during a call: the other side leaving is only '
        'visible through sync', () {
      for (final mode in [
        NotificationDeliveryMode.fcm,
        NotificationDeliveryMode.unifiedPush,
      ]) {
        expect(
          shouldPauseBackgroundSync(
            AppLifecycleState.paused,
            mode,
            inCall: true,
          ),
          isFalse,
          reason: mode.toString(),
        );
      }
    });

    test('does not pause on states other than paused', () {
      for (final state in [
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        expect(
          shouldPauseBackgroundSync(
            state,
            NotificationDeliveryMode.fcm,
            inCall: false,
          ),
          isFalse,
          reason: state.toString(),
        );
      }
    });
  });

  group('shouldResumeBackgroundSync', () {
    test('resumes on foreground when delivery is FCM', () {
      expect(
        shouldResumeBackgroundSync(
          AppLifecycleState.resumed,
          NotificationDeliveryMode.fcm,
        ),
        isTrue,
      );
    });

    test('never needs to resume when delivery is the background service', () {
      expect(
        shouldResumeBackgroundSync(
          AppLifecycleState.resumed,
          NotificationDeliveryMode.backgroundService,
        ),
        isFalse,
      );
    });

    test('does not resume on states other than resumed', () {
      for (final state in [
        AppLifecycleState.paused,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        expect(
          shouldResumeBackgroundSync(state, NotificationDeliveryMode.fcm),
          isFalse,
          reason: state.toString(),
        );
      }
    });
  });
}
