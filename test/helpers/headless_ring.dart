import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';

import 'fake_call_style_channel.dart';
import 'fake_local_notifications.dart';
import 'fake_matrix.dart';
import 'native_method_calls.dart';
import 'push_test_client.dart';

PushTestClient ringingPushClient({bool rings = true}) {
  final client = PushTestClient()..setUserId('@me:example.org');
  if (rings) {
    client.pushedEvent = (_) => buildTestEvent(
      buildTestRoom(client),
      eventId: r'$invite',
      senderId: '@bob:example.org',
      content: const {
        'msgtype': 'im.zuno.call_invite',
        'call_id': 'call1',
        'kind': 'voice',
        'body': 'Incoming call',
      },
    );
  }
  return client;
}

RecordedMethodCalls installHeadlessRingChannels() {
  ringRateLimiter.clear();
  installFakeLocalNotifications();
  installSilentNotificationSideChannels();
  silenceMethodChannels(const ['zuno/calls', 'zuno/vibration']);
  return installFakeCallStyleChannel();
}
