import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart'
    show RingingCallInfo;
import 'package:zuno/core/calls/notifications/ring_notification.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

Map<String, Object?> _ringOnScreen() => {
  'id': 4002,
  'channelId': 'calls_ringing',
  'groupKey': null,
  'tag': null,
  'title': 'Incoming voice call',
  'body': 'Bob',
  'payload': null,
  'bigText': null,
};

void main() {
  late RecordedNotifications notifications;
  late RecordedCallStyleCalls callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
  });

  tearDown(() async {
    await pumpEventQueue();
    await NotificationSoundPlayer.instance.stopIncomingRing();
  });

  Future<void> ring(IncomingCallPresenter presenter) => presenter.showIncoming(
    callerName: 'Bob',
    callerId: '@bob:example.org',
    isVideo: true,
    roomId: '!room:example.org',
    callId: 'call1',
    isGroupCall: true,
    avatarBytes: Uint8List.fromList([1, 2, 3]),
  );

  Future<RingingCallInfo?> remembered() async =>
      readRingingCall(await SharedPreferences.getInstance());

  group('picking the presenter', () {
    test('android rings through its own full-screen notification', () {
      expect(
        incomingCallPresenterFor(androidCapabilities),
        isA<AndroidIncomingCallPresenter>(),
      );
    });

    test('without full-screen ringing there is nothing to present with', () {
      expect(
        incomingCallPresenterFor(iosCapabilities),
        isA<NoopIncomingCallPresenter>(),
      );
      expect(
        incomingCallPresenterFor(
          capabilitiesLike(androidCapabilities, fullScreenIntent: false),
        ),
        isA<NoopIncomingCallPresenter>(),
      );
    });

    test('the provider follows the platform capabilities', () {
      final android = ProviderContainer();
      addTearDown(android.dispose);
      final ios = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(iosCapabilities),
        ],
      );
      addTearDown(ios.dispose);

      expect(
        android.read(incomingCallPresenterProvider),
        isA<AndroidIncomingCallPresenter>(),
      );
      expect(
        ios.read(incomingCallPresenterProvider),
        isA<NoopIncomingCallPresenter>(),
      );
    });
  });

  group('the android presenter', () {
    const presenter = AndroidIncomingCallPresenter();

    test('posts the call-style ring with everything its actions need, and '
        'remembers the call', () async {
      await ring(presenter);

      expect((callStyle.lastShow.arguments as Map).cast<String, Object?>(), {
        'channelId': 'calls_ringing_group',
        'title': 'Incoming video call',
        'callerName': 'Bob',
        'callerId': '@bob:example.org',
        'isVideo': true,
        'roomId': '!room:example.org',
        'callId': 'call1',
        'avatarBytes': Uint8List.fromList([1, 2, 3]),
      });
      expect((await remembered())?.callId, 'call1');
    });

    test('reports the ring only while its notification is on screen', () async {
      await ring(presenter);

      notifications.active = [_ringOnScreen()];
      expect((await presenter.activeRing())?.callId, 'call1');

      notifications.active = const [];
      expect(await presenter.activeRing(), isNull);
    });

    test(
      'cancelling takes the notification down and forgets the call',
      () async {
        await ring(presenter);

        await presenter.cancelIncoming();
        notifications.active = [_ringOnScreen()];

        expect(callStyle.calls.map((c) => c.method), [
          'showIncomingCallStyle',
          'cancelIncomingCallStyle',
        ]);
        expect(await remembered(), isNull);
        expect(await presenter.activeRing(), isNull);
      },
    );
  });

  group('the presenter for a platform without full-screen ringing', () {
    final presenter = incomingCallPresenterFor(iosCapabilities);

    test(
      'posts nothing, rings nothing, remembers nothing, reports no ring',
      () async {
        await ring(presenter);
        await pumpEventQueue();
        notifications.active = [_ringOnScreen()];

        expect(await presenter.activeRing(), isNull);
        await presenter.cancelIncoming();

        expect(callStyle.calls, isEmpty);
        expect(notifications.methods, isEmpty);
        expect(NotificationSoundPlayer.instance.ownsIncomingRing, isFalse);
        expect(await remembered(), isNull);
      },
    );

    test('an incoming call handed to it goes nowhere', () async {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));

      await postRingNotification(
        IncomingCall(
          room: room,
          callId: 'call1',
          callerId: '@bob:example.org',
          kind: CallKind.voice,
        ),
        presenter: presenter,
      );

      expect(callStyle.calls, isEmpty);
      expect(await remembered(), isNull);
    });
  });
}
