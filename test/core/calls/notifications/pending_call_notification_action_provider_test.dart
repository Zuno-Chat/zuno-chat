import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/pending_call_notification_action_provider.dart';

CallNotificationResponse _response({
  CallNotificationAction action = CallNotificationAction.accept,
}) => CallNotificationResponse(
  action: action,
  call: (
    roomId: '!room:example.org',
    callId: 'c1',
    callerId: '@alice:example.org',
    isVideo: false,
  ),
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pendingCallNotificationActionProvider);
  });

  test('starts with no pending action', () {
    expect(container.read(pendingCallNotificationActionProvider), isNull);
  });

  test('an action fired by the plugin becomes the pending action', () async {
    CallNotificationService.instance.onActionForTest(_response());
    await pumpEventQueue();
    final pending = container.read(pendingCallNotificationActionProvider);
    expect(pending?.action, CallNotificationAction.accept);
    expect(pending?.call.roomId, '!room:example.org');
    expect(pending?.call.callId, 'c1');
  });

  test('consume() returns and clears the pending action', () async {
    CallNotificationService.instance.onActionForTest(
      _response(action: CallNotificationAction.decline),
    );
    await pumpEventQueue();
    expect(
      container.read(pendingCallNotificationActionProvider)?.action,
      CallNotificationAction.decline,
    );
    final consumed = container
        .read(pendingCallNotificationActionProvider.notifier)
        .consume();
    expect(consumed?.action, CallNotificationAction.decline);
    expect(container.read(pendingCallNotificationActionProvider), isNull);
  });

  test('consume() returns null when nothing is pending', () {
    final consumed = container
        .read(pendingCallNotificationActionProvider.notifier)
        .consume();
    expect(consumed, isNull);
  });
}
