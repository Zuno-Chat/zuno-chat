import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_local_notifications.dart';

void main() {
  late RecordedCallStyleCalls callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
  });

  Future<Map<String, Object?>> postRing({
    bool isVideo = false,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
  }) async {
    await CallNotificationService.instance.showIncomingCall(
      callerName: 'Bob',
      callerId: '@bob:example.org',
      isVideo: isVideo,
      roomId: '!room:example.org',
      callId: 'call1',
      isGroupCall: isGroupCall,
      avatarBytes: avatarBytes,
    );
    return (callStyle.lastShow.arguments as Map).cast<String, Object?>();
  }

  test('names the caller, and says which kind of call it is', () async {
    final video = await postRing(isVideo: true);
    expect(video['title'], 'Incoming video call');
    expect(video['callerName'], 'Bob');

    callStyle.clear();
    final voice = await postRing();
    expect(voice['title'], 'Incoming voice call');
  });

  test('rings on the direct channel by default, the group channel for a '
      'group call', () async {
    final direct = await postRing();
    expect(direct['channelId'], 'calls_ringing');

    callStyle.clear();
    final group = await postRing(isGroupCall: true);
    expect(group['channelId'], 'calls_ringing_group');
  });

  test('carries the call it is for, so an action can act on it', () async {
    final args = await postRing();

    expect(args['roomId'], '!room:example.org');
    expect(args['callId'], 'call1');
    expect(args['callerId'], '@bob:example.org');
  });

  test('passes the avatar bytes through when given, and null when not',
      () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final withAvatar = await postRing(avatarBytes: bytes);
    expect(withAvatar['avatarBytes'], bytes);

    callStyle.clear();
    final withoutAvatar = await postRing();
    expect(withoutAvatar['avatarBytes'], isNull);
  });
}
