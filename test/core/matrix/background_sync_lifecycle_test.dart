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
          keepSyncAlive: false,
        ),
        isTrue,
      );
    });

    test('pauses on background when delivery is UnifiedPush', () {
      expect(
        shouldPauseBackgroundSync(
          AppLifecycleState.paused,
          NotificationDeliveryMode.unifiedPush,
          keepSyncAlive: false,
        ),
        isTrue,
      );
    });

    test('never pauses when delivery is the background service', () {
      expect(
        shouldPauseBackgroundSync(
          AppLifecycleState.paused,
          NotificationDeliveryMode.backgroundService,
          keepSyncAlive: false,
        ),
        isFalse,
      );
    });

    test('never pauses while a call or a live share needs sync: the other '
        'side leaving and watch signals arrive only through sync', () {
      for (final mode in [
        NotificationDeliveryMode.fcm,
        NotificationDeliveryMode.unifiedPush,
      ]) {
        expect(
          shouldPauseBackgroundSync(
            AppLifecycleState.paused,
            mode,
            keepSyncAlive: true,
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
            keepSyncAlive: false,
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

  group('shouldLongPollInBackground', () {
    test('long-polls in the background for a live share alone', () {
      expect(
        shouldLongPollInBackground(
          AppLifecycleState.paused,
          NotificationDeliveryMode.fcm,
          forCall: false,
          forLiveShare: true,
        ),
        isTrue,
      );
    });

    test('a call or ring keeps the regular loop', () {
      expect(
        shouldLongPollInBackground(
          AppLifecycleState.paused,
          NotificationDeliveryMode.fcm,
          forCall: true,
          forLiveShare: true,
        ),
        isFalse,
      );
    });

    test('never in front, never without a share, never for the background '
        'service', () {
      expect(
        shouldLongPollInBackground(
          AppLifecycleState.resumed,
          NotificationDeliveryMode.fcm,
          forCall: false,
          forLiveShare: true,
        ),
        isFalse,
      );
      expect(
        shouldLongPollInBackground(
          AppLifecycleState.paused,
          NotificationDeliveryMode.fcm,
          forCall: false,
          forLiveShare: false,
        ),
        isFalse,
      );
      expect(
        shouldLongPollInBackground(
          AppLifecycleState.paused,
          NotificationDeliveryMode.backgroundService,
          forCall: false,
          forLiveShare: true,
        ),
        isFalse,
      );
    });
  });
}
